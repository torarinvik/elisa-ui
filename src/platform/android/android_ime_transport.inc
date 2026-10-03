#include "android_ime_queue.h"
#include "../common/utf8_utf16.h"
#include <math.h>

extern uint64_t elisa_android_ime_owner(void);
extern int32_t elisa_android_ime_action(uint64_t owner, int32_t action);
extern int32_t elisa_android_ime_selection(uint64_t owner, int32_t start, int32_t stop);
extern int32_t elisa_android_ime_composing_region(uint64_t owner, int32_t start, int32_t stop);
extern int32_t elisa_android_ime_delete_surrounding(uint64_t owner, int32_t before, int32_t after);
extern int32_t elisa_android_ime_delete_codepoints(uint64_t owner, int32_t before, int32_t after);
extern int32_t elisa_android_ime_dispatch(uint64_t owner, int32_t kind,
        const char *text, int32_t length, int32_t cursor);
static elisa_ime_queue elisa_ime_commands = ELISA_IME_QUEUE_INITIALIZER;
// Owner-thread state, not read or written by JNI producers.
static uint64_t elisa_ime_consuming_batch;
static int32_t elisa_ime_connection_purpose = -1;
static int32_t elisa_ime_selection_start, elisa_ime_selection_end;
static int32_t elisa_ime_mark_start = -1, elisa_ime_mark_end = -1;
extern const char *elisa_android_ime_readback_text(void);
static unsigned char elisa_ime_readback_bytes[ELISA_IME_QUEUE_BYTES];
static size_t elisa_ime_readback_length;
static int elisa_ime_readback_allowed;
extern int32_t elisa_android_ime_selection_position(int32_t endpoint);
extern uint64_t elisa_android_ime_take_menu_request(void);
static uint64_t elisa_ime_menu_serial, elisa_ime_published_menu_serial;
typedef struct { uint64_t owner; int32_t purpose, start, end, mark_start, mark_end; uint64_t menu_serial; } elisa_ime_snapshot;

static elisa_ime_snapshot elisa_ime_connection_snapshot(void) {
    pthread_mutex_lock(&elisa_ime_commands.mutex);
    elisa_ime_snapshot snapshot = {elisa_ime_commands.owner, elisa_ime_connection_purpose,
        elisa_ime_selection_start, elisa_ime_selection_end, elisa_ime_mark_start, elisa_ime_mark_end,
        elisa_ime_published_menu_serial};
    pthread_mutex_unlock(&elisa_ime_commands.mutex);
    return snapshot;
}

int32_t elisa_android_ime_publish_state(uint64_t owner, int32_t purpose, int32_t start, int32_t end) {
    if (owner && owner == elisa_ime_consuming_batch) return 0;
    elisa_ime_consuming_batch = 0;
    uint64_t menu_owner = elisa_android_ime_take_menu_request();
    int32_t mark_start = owner ? elisa_android_ime_selection_position(2) : -1;
    int32_t mark_end = owner ? elisa_android_ime_selection_position(3) : -1;
    purpose = owner ? purpose : -1;
    start = owner ? start : 0; end = owner ? end : 0;
    const char *text = owner ? elisa_android_ime_readback_text() : NULL;
    int allowed = text != NULL && purpose >= 0 && purpose <= 5 && purpose != 1;
    size_t text_length = 0;
    if (allowed) while (text_length < ELISA_IME_QUEUE_BYTES - 1 && text[text_length]) ++text_length;
    pthread_mutex_lock(&elisa_ime_commands.mutex);
    int32_t changed = owner != elisa_ime_commands.owner || purpose != elisa_ime_connection_purpose ||
        start != elisa_ime_selection_start || end != elisa_ime_selection_end ||
        mark_start != elisa_ime_mark_start || mark_end != elisa_ime_mark_end;
    changed |= allowed != elisa_ime_readback_allowed || text_length != elisa_ime_readback_length;
    if (allowed && !changed && text_length) changed = memcmp(text, elisa_ime_readback_bytes, text_length) != 0;
    if (owner != elisa_ime_commands.owner) elisa_ime_published_menu_serial = 0;
    if (owner && menu_owner == owner) {
        ++elisa_ime_menu_serial;
        if (!elisa_ime_menu_serial) ++elisa_ime_menu_serial;
        elisa_ime_published_menu_serial = elisa_ime_menu_serial;
        changed = 1;
    }
    elisa_ime_queue_owner_locked(&elisa_ime_commands, owner);
    elisa_ime_connection_purpose = owner ? purpose : -1;
    elisa_ime_selection_start = owner ? start : 0;
    elisa_ime_selection_end = owner ? end : 0;
    elisa_ime_mark_start = mark_start; elisa_ime_mark_end = mark_end;
    elisa_ime_queue_scrub(elisa_ime_readback_bytes, sizeof(elisa_ime_readback_bytes));
    elisa_ime_readback_length = 0;
    elisa_ime_readback_allowed = text != NULL && purpose >= 0 && purpose <= 5 && purpose != 1;
    if (elisa_ime_readback_allowed) {
        while (elisa_ime_readback_length < ELISA_IME_QUEUE_BYTES - 1 && text[elisa_ime_readback_length]) {
            elisa_ime_readback_bytes[elisa_ime_readback_length] = (unsigned char)text[elisa_ime_readback_length];
            ++elisa_ime_readback_length;
        }
    }
    pthread_mutex_unlock(&elisa_ime_commands.mutex);
    return changed;
}
static int elisa_ime_insets_pending;
static uint64_t elisa_ime_insets_owner;
static float elisa_ime_insets_bottom;
static int32_t elisa_ime_insets_visible;
static void elisa_ime_deliver_insets(float bottom, int32_t visible);
static void elisa_ime_deliver_report(const char *label);

// Coalesced geometry, not text: only the latest inset is useful to layout.
static int elisa_ime_enqueue_insets(float bottom, int32_t visible) {
    if (!isfinite(bottom) || bottom < 0 || (visible != 0 && visible != 1)) return 0;
    pthread_mutex_lock(&elisa_ime_commands.mutex);
    elisa_ime_insets_owner = elisa_ime_commands.owner;
    elisa_ime_insets_bottom = visible ? bottom : 0;
    elisa_ime_insets_visible = visible;
    elisa_ime_insets_pending = 1;
    pthread_mutex_unlock(&elisa_ime_commands.mutex);
    return 1;
}

static void elisa_ime_drain_insets(void) {
    pthread_mutex_lock(&elisa_ime_commands.mutex);
    int deliver = elisa_ime_insets_pending && elisa_ime_insets_owner == elisa_ime_commands.owner;
    float bottom = elisa_ime_insets_bottom;
    int32_t visible = elisa_ime_insets_visible;
    elisa_ime_insets_pending = 0;
    pthread_mutex_unlock(&elisa_ime_commands.mutex);
    if (deliver) elisa_ime_deliver_insets(bottom, visible);
}

// Owner thread only. Closing or changing a connection erases pending secrets.
void elisa_android_ime_publish_owner(uint64_t owner) {
    if (owner != elisa_ime_consuming_batch) elisa_ime_consuming_batch = 0;
    pthread_mutex_lock(&elisa_ime_commands.mutex);
    if (owner != elisa_ime_commands.owner) {
        elisa_ime_published_menu_serial = 0;
        elisa_ime_connection_purpose = -1;
        elisa_ime_selection_start = elisa_ime_selection_end = 0;
        elisa_ime_mark_start = elisa_ime_mark_end = -1;
        elisa_ime_queue_scrub(elisa_ime_readback_bytes, sizeof(elisa_ime_readback_bytes));
        elisa_ime_readback_length = 0;
        elisa_ime_readback_allowed = 0;
    }
    elisa_ime_queue_owner_locked(&elisa_ime_commands, owner);
    pthread_mutex_unlock(&elisa_ime_commands.mutex);
}

// Java may only read the published identity, not retained widget state.
static uint64_t elisa_ime_connection_owner(void) {
    pthread_mutex_lock(&elisa_ime_commands.mutex);
    uint64_t owner = elisa_ime_commands.owner;
    pthread_mutex_unlock(&elisa_ime_commands.mutex);
    return owner;
}

// Return a plain UTF-16 slice from the same publication as its selection.
// -1 is denied/retired; zero is an allowed empty result.
static int32_t elisa_ime_readback(uint64_t owner, int32_t mode, int32_t count, uint16_t *output) {
    if (!owner || mode < 0 || mode > 2 || count < 0 || !output) return -1;
    pthread_mutex_lock(&elisa_ime_commands.mutex);
    if (owner != elisa_ime_commands.owner || !elisa_ime_readback_allowed) {
        pthread_mutex_unlock(&elisa_ime_commands.mutex);
        return -1;
    }
    uint16_t units[ELISA_IME_QUEUE_BYTES];
    size_t length = elisa_utf8_to_utf16(elisa_ime_readback_bytes, elisa_ime_readback_length, units, ELISA_IME_QUEUE_BYTES);
    size_t anchor = elisa_ime_selection_start < 0 ? 0 : (size_t)elisa_ime_selection_start;
    size_t caret = elisa_ime_selection_end < 0 ? 0 : (size_t)elisa_ime_selection_end;
    if (anchor > length) anchor = length;
    if (caret > length) caret = length;
    size_t start = anchor < caret ? anchor : caret;
    size_t stop = anchor > caret ? anchor : caret;
    if (mode == 0) {
        stop = start;
        start = (size_t)count < stop ? stop - (size_t)count : 0;
        if (start < stop && units[start] >= 0xdc00 && units[start] <= 0xdfff) ++start;
    } else if (mode == 1) {
        start = stop;
        size_t remaining = length - start;
        stop = start + ((size_t)count < remaining ? (size_t)count : remaining);
        if (stop > start && units[stop - 1] >= 0xd800 && units[stop - 1] <= 0xdbff) --stop;
    }
    size_t copied = stop - start;
    if (copied) memcpy(output, units + start, copied * sizeof(*output));
    elisa_ime_queue_scrub(units, sizeof(units));
    pthread_mutex_unlock(&elisa_ime_commands.mutex);
    return (int32_t)copied;
}

static int32_t elisa_ime_document(uint64_t owner, uint16_t *output, int32_t *positions) {
    if (!owner || !output || !positions) return -1;
    pthread_mutex_lock(&elisa_ime_commands.mutex);
    if (owner != elisa_ime_commands.owner || !elisa_ime_readback_allowed) {
        pthread_mutex_unlock(&elisa_ime_commands.mutex);
        return -1;
    }
    size_t length = elisa_utf8_to_utf16(elisa_ime_readback_bytes, elisa_ime_readback_length, output, ELISA_IME_QUEUE_BYTES);
    positions[0] = elisa_ime_selection_start;
    positions[1] = elisa_ime_selection_end;
    for (size_t i = 0; i < 2; ++i) {
        if (positions[i] < 0) positions[i] = 0;
        if ((size_t)positions[i] > length) positions[i] = (int32_t)length;
    }
    pthread_mutex_unlock(&elisa_ime_commands.mutex);
    return (int32_t)length;
}

static int elisa_ime_enqueue_utf16(uint64_t owner, int32_t kind, int32_t cursor,
        const uint16_t *units, size_t count) {
    if (count > ELISA_IME_QUEUE_BYTES || (count && !units)) return 0;
    // Convert fully, then reject overflow rather than acknowledge a prefix.
    unsigned char bytes[ELISA_IME_QUEUE_BYTES * 3];
    size_t length = elisa_utf16_to_utf8(units, count, bytes, sizeof(bytes));
    int accepted = elisa_ime_queue_push(&elisa_ime_commands, owner, kind, cursor, bytes, length);
    elisa_ime_queue_scrub(bytes, sizeof(bytes));
    return accepted;
}

// A bounded batch avoids starving native lifecycle/input processing.
void elisa_android_ime_drain(void) {
    elisa_android_ime_publish_owner(elisa_android_ime_owner());
    elisa_ime_drain_insets();
    elisa_android_ime_publish_owner(elisa_android_ime_owner());
    for (size_t count = 0; count < ELISA_IME_QUEUE_CAPACITY; ++count) {
        elisa_ime_command command;
        if (!elisa_ime_queue_pop(&elisa_ime_commands, &command)) break;
        if (command.kind == 8) {
            if (command.owner == elisa_android_ime_owner()) elisa_ime_consuming_batch = command.owner;
        } else if (command.kind == 9) {
            if (command.owner == elisa_ime_consuming_batch) {
                elisa_ime_consuming_batch = 0;
                if (command.cursor != 0)
                    (void)elisa_android_ime_dispatch(command.owner, 3, NULL, 0, 0);
            }
        } else if (command.kind == 10) {
            (void)elisa_android_ime_action(command.owner, command.cursor);
        } else if (command.kind == 2) {
            char label[ELISA_IME_QUEUE_BYTES + 1];
            memcpy(label, command.bytes, command.length);
            label[command.length] = 0;
            if (command.owner == elisa_android_ime_owner()) elisa_ime_deliver_report(label);
            elisa_ime_queue_scrub(label, sizeof(label));
        } else if (command.kind >= 4 && command.kind <= 7) {
            int32_t stop;
            if (command.length == sizeof(stop)) {
                memcpy(&stop, command.bytes, sizeof(stop));
                if (command.kind == 4)
                    (void)elisa_android_ime_selection(command.owner, command.cursor, stop);
                else if (command.kind == 5)
                    (void)elisa_android_ime_delete_surrounding(command.owner, command.cursor, stop);
                else if (command.kind == 6)
                    (void)elisa_android_ime_delete_codepoints(command.owner, command.cursor, stop);
                else
                    (void)elisa_android_ime_composing_region(command.owner, command.cursor, stop);
            }
        } else {
            (void)elisa_android_ime_dispatch(command.owner, command.kind,
                    (const char *)command.bytes, (int32_t)command.length, command.cursor);
        }
        elisa_ime_queue_scrub(&command, sizeof(command));
        // An application callback can retire focus during dispatch.
        elisa_android_ime_publish_owner(elisa_android_ime_owner());
    }
}
