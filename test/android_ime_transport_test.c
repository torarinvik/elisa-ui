#include <stdint.h>
#include <stdio.h>
#include <assert.h>
#include <stdatomic.h>
static uint64_t current_owner = 7;
static int delivered;
static int finishes;
static const char *published_text = "AB😀Z";
const char *elisa_android_ime_readback_text(void) { return published_text; }
int32_t elisa_android_ime_selection_position(int32_t endpoint) { return endpoint == 2 ? 1 : 3; }
static int selections;
static int actions;
static _Atomic uint64_t menu_request;
uint64_t elisa_android_ime_take_menu_request(void) {
    return atomic_exchange(&menu_request, 0);
}
int32_t elisa_android_ime_action(uint64_t owner, int32_t action) {
    assert(owner == current_owner && action >= 1 && action <= 4);
    ++actions;
    return 1;
}
static int regions;
int32_t elisa_android_ime_composing_region(uint64_t owner, int32_t start, int32_t stop) {
    assert(owner == current_owner && start == 5 && stop == 3);
    ++regions;
    return 1;
}
static int deletions;
static int scalar_deletions;
int32_t elisa_android_ime_delete_codepoints(uint64_t owner, int32_t before, int32_t after) {
    assert(owner == current_owner && before == 5 && after == 3);
    ++scalar_deletions;
    return 1;
}
int32_t elisa_android_ime_delete_surrounding(uint64_t owner, int32_t before, int32_t after) {
    assert(owner == current_owner && before == 5 && after == 3);
    ++deletions;
    return 1;
}
int32_t elisa_android_ime_selection(uint64_t owner, int32_t start, int32_t stop) {
    assert(owner == current_owner && start == 5 && stop == 3);
    ++selections;
    return 1;
}
static int retire_on_dispatch;
static int inset_calls;
static float inset_bottom;
static int32_t inset_visible;
static int reports, delivered_at_report;
static void elisa_ime_deliver_report(const char *label) {
    assert(label[0] == 'r' && label[1] == 0);
    ++reports; delivered_at_report = delivered;
}
static void elisa_ime_deliver_insets(float bottom, int32_t visible) {
    ++inset_calls; inset_bottom = bottom; inset_visible = visible;
}
uint64_t elisa_android_ime_owner(void) { return current_owner; }
int32_t elisa_android_ime_dispatch(uint64_t owner, int32_t kind,
        const char *text, int32_t length, int32_t cursor) {
    if (kind == 3) {
        assert(owner == current_owner && length == 0);
        ++finishes;
        return 1;
    }
    assert(owner == current_owner && kind == 1 && length == 1 && text[0] == 'x' && cursor == 1);
    ++delivered;
    if (retire_on_dispatch) ++current_owner;
    return 1;
}
#include "../src/platform/android/android_ime_transport.inc"
static void *publish_snapshots(void *unused) {
    (void)unused;
    for (uint64_t owner = 1; owner <= 10000; ++owner)
        elisa_android_ime_publish_state(owner, (int32_t)(owner % 2), (int32_t)owner, (int32_t)owner + 1);
    return NULL;
}
int main(void) {
    elisa_android_ime_publish_state(current_owner, 1, 8, 2);
    elisa_ime_snapshot snapshot = elisa_ime_connection_snapshot();
    assert(snapshot.owner == 7 && snapshot.purpose == 1 && snapshot.start == 8 && snapshot.end == 2);
    assert(elisa_ime_connection_owner() == 7);
    assert(elisa_ime_queue_push(&elisa_ime_commands, 7, 1, 1, "x", 1));
    elisa_android_ime_drain();
    assert(delivered == 1 && elisa_ime_commands.count == 0);
    assert(elisa_ime_queue_push(&elisa_ime_commands, 7, 1, 1, "x", 1));
    assert(elisa_ime_queue_push(&elisa_ime_commands, 7, 1, 1, "x", 1));
    retire_on_dispatch = 1;
    elisa_android_ime_drain();
    assert(delivered == 2 && elisa_ime_connection_owner() == 8);
    assert(elisa_ime_commands.count == 0);
    for (size_t i = 0; i < sizeof(elisa_ime_commands.commands); ++i)
        assert(((unsigned char *)elisa_ime_commands.commands)[i] == 0);
    assert(!elisa_ime_queue_push(&elisa_ime_commands, 7, 1, 1, "x", 1));
    assert(elisa_ime_queue_push(&elisa_ime_commands, 8, 1, 1, "x", 1));
    current_owner = 0;
    elisa_android_ime_drain();
    assert(delivered == 2 && elisa_ime_connection_owner() == 0);
    current_owner = 9;
    elisa_android_ime_publish_owner(current_owner);
    uint16_t units[1025];
    for (size_t i = 0; i < 1025; ++i) units[i] = 'a';
    assert(!elisa_ime_enqueue_utf16(9, 1, 1, units, 1025));
    assert(elisa_ime_enqueue_utf16(9, 1, 1, units, 1024));
    elisa_ime_command command;
    assert(elisa_ime_queue_pop(&elisa_ime_commands, &command) && command.length == 1024);
    elisa_ime_queue_scrub(&command, sizeof(command));
    for (size_t i = 0; i < 1025; ++i) units[i] = 0x4f60;
    assert(!elisa_ime_enqueue_utf16(9, 1, 1, units, 342));
    assert(elisa_ime_commands.count == 0);
    units[0] = 0xd83d; units[1] = 0xdc4b;
    assert(elisa_ime_enqueue_utf16(9, 0, -1, units, 2));
    assert(elisa_ime_queue_pop(&elisa_ime_commands, &command));
    assert(command.kind == 0 && command.cursor == -1 && command.length == 4);
    assert(command.bytes[0] == 0xf0 && command.bytes[3] == 0x8b);
    elisa_ime_queue_scrub(&command, sizeof(command));
    assert(!elisa_ime_enqueue_utf16(8, 1, 1, units, 2));
    assert(!elisa_ime_enqueue_utf16(9, 1, 1, NULL, 1));
    assert(elisa_ime_enqueue_insets(100, 1));
    assert(elisa_ime_enqueue_insets(200, 1));
    assert(inset_calls == 0);
    elisa_android_ime_drain();
    assert(inset_calls == 1 && inset_bottom == 200 && inset_visible == 1);
    elisa_android_ime_drain();
    assert(inset_calls == 1);
    assert(!elisa_ime_enqueue_insets(NAN, 1));
    assert(!elisa_ime_enqueue_insets(-1, 1));
    assert(!elisa_ime_enqueue_insets(1, 2));
    assert(elisa_ime_enqueue_insets(300, 1));
    ++current_owner;
    elisa_android_ime_drain();
    assert(inset_calls == 1);
    assert(elisa_ime_enqueue_insets(300, 0));
    elisa_android_ime_drain();
    assert(inset_calls == 2 && inset_bottom == 0 && inset_visible == 0);
    retire_on_dispatch = 0;
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 1, 1, "x", 1));
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 2, 0, "r", 1));
    assert(reports == 0);
    elisa_android_ime_drain();
    assert(reports == 1 && delivered_at_report == 3);
    retire_on_dispatch = 1;
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 1, 1, "x", 1));
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 2, 0, "r", 1));
    elisa_android_ime_drain();
    assert(delivered == 4 && reports == 1);
    snapshot = elisa_ime_connection_snapshot();
    assert(snapshot.owner == current_owner && snapshot.purpose == -1 && snapshot.start == 0 && snapshot.end == 0);
    elisa_android_ime_publish_state(current_owner, 2, 8, 2);
    snapshot = elisa_ime_connection_snapshot();
    assert(snapshot.owner == current_owner && snapshot.purpose == 2);
    elisa_android_ime_publish_state(0, 2, 8, 2);
    snapshot = elisa_ime_connection_snapshot();
    assert(snapshot.owner == 0 && snapshot.purpose == -1 && snapshot.start == 0 && snapshot.end == 0);
    elisa_android_ime_publish_state(current_owner, 0, 8, 2);
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 3, 0, NULL, 0));
    assert(finishes == 0);
    elisa_android_ime_drain();
    assert(finishes == 1 && delivered == 4);
    int32_t selection_end = 3;
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 4, 5, &selection_end, sizeof(selection_end)));
    assert(selections == 0);
    elisa_android_ime_drain();
    assert(selections == 1);
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 5, 5, &selection_end, sizeof(selection_end)));
    assert(deletions == 0);
    elisa_android_ime_drain();
    assert(deletions == 1);
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 6, 5, &selection_end, sizeof(selection_end)));
    assert(scalar_deletions == 0);
    elisa_android_ime_drain();
    assert(scalar_deletions == 1);
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 7, 5, &selection_end, sizeof(selection_end)));
    assert(regions == 0);
    elisa_android_ime_drain();
    assert(regions == 1);
    assert(!elisa_ime_queue_push(&elisa_ime_commands, current_owner, 10, 0, NULL, 0));
    assert(!elisa_ime_queue_push(&elisa_ime_commands, current_owner, 10, 5, NULL, 0));
    assert(!elisa_ime_queue_push(&elisa_ime_commands, current_owner, 10, 2, "x", 1));
    for (int action = 1; action <= 4; ++action)
        assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 10, action, NULL, 0));
    assert(actions == 0);
    elisa_android_ime_drain();
    assert(actions == 4);
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 7, 5, "x", 1));
    elisa_android_ime_drain();
    assert(regions == 1);
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 5, 5, "x", 1));
    elisa_android_ime_drain();
    assert(deletions == 1);
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 4, 5, "x", 1));
    elisa_android_ime_drain();
    assert(selections == 1);
    elisa_android_ime_publish_state(0, 0, 0, 0);
    pthread_t publisher;
    assert(pthread_create(&publisher, NULL, publish_snapshots, NULL) == 0);
    for (int i = 0; i < 10000; ++i) {
        snapshot = elisa_ime_connection_snapshot();
        assert(snapshot.owner ? snapshot.purpose == (int32_t)(snapshot.owner % 2) : snapshot.purpose == -1);
        assert(snapshot.owner ? snapshot.start == (int32_t)snapshot.owner && snapshot.end == (int32_t)snapshot.owner + 1 : snapshot.start == 0 && snapshot.end == 0);
        assert(snapshot.owner ? snapshot.mark_start == 1 && snapshot.mark_end == 3 : snapshot.mark_start == -1 && snapshot.mark_end == -1);
    }
    assert(pthread_join(publisher, NULL) == 0);
    uint16_t readback[ELISA_IME_QUEUE_BYTES];
    elisa_android_ime_publish_state(10001, 0, 4, 2);
    int32_t document_positions[2];
    assert(elisa_ime_document(10001, readback, document_positions) == 5);
    assert(document_positions[0] == 4 && document_positions[1] == 2 && readback[2] == 0xd83d && readback[3] == 0xde00);
    assert(elisa_ime_document(10000, readback, document_positions) == -1);
    assert(elisa_android_ime_publish_state(10001, 0, 4, 2) == 0);
    published_text = "AC😀Z";
    assert(elisa_android_ime_publish_state(10001, 0, 4, 2) == 1);
    assert(elisa_android_ime_publish_state(10001, 0, 4, 2) == 0);
    published_text = "AB😀Z";
    assert(elisa_android_ime_publish_state(10001, 0, 4, 2) == 1);
    assert(elisa_ime_readback(10001, 2, 0, readback) == 2 && readback[0] == 0xd83d && readback[1] == 0xde00);
    assert(elisa_ime_readback(10001, 0, 1, readback) == 1 && readback[0] == 'B');
    assert(elisa_ime_readback(10001, 1, 1, readback) == 1 && readback[0] == 'Z');
    assert(elisa_ime_readback(10000, 2, 0, readback) == -1);
    assert(elisa_ime_readback(10001, 0, -1, readback) == -1);
    elisa_android_ime_publish_state(10001, 0, 4, 4);
    assert(elisa_ime_readback(10001, 0, 1, readback) == 0);
    elisa_android_ime_publish_state(10001, 0, 2, 2);
    assert(elisa_ime_readback(10001, 1, 1, readback) == 0);
    elisa_android_ime_publish_state(10001, 1, 2, 2);
    assert(elisa_ime_document(10001, readback, document_positions) == -1);
    assert(elisa_ime_readback(10001, 2, 0, readback) == -1 && elisa_ime_readback_length == 0);
    for (size_t i = 0; i < sizeof(elisa_ime_readback_bytes); ++i) assert(elisa_ime_readback_bytes[i] == 0);
    current_owner = 10002;
    retire_on_dispatch = 0;
    published_text = "AB😀Z";
    elisa_android_ime_publish_state(current_owner, 0, 4, 2);
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 8, 0, NULL, 0));
    elisa_android_ime_drain();
    assert(elisa_ime_consuming_batch == current_owner);
    published_text = "AC😀Z";
    assert(elisa_android_ime_publish_state(current_owner, 0, 4, 2) == 0);
    assert(elisa_ime_document(current_owner, readback, document_positions) == 5 && readback[1] == 'B');
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 9, 0, NULL, 0));
    elisa_android_ime_drain();
    assert(elisa_ime_consuming_batch == 0);
    assert(elisa_android_ime_publish_state(current_owner, 0, 4, 2) == 1);
    assert(elisa_ime_document(current_owner, readback, document_positions) == 5 && readback[1] == 'C');
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 8, 0, NULL, 0));
    elisa_android_ime_drain();
    ++current_owner;
    elisa_android_ime_drain();
    assert(elisa_ime_consuming_batch == 0 && !elisa_ime_commands.batch_open);
    elisa_android_ime_publish_state(current_owner, 0, 4, 2);
    int delivered_before_close = delivered, finishes_before_close = finishes;
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 8, 0, NULL, 0));
    for (int i = 0; i < ELISA_IME_QUEUE_CAPACITY - 2; ++i)
        assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 1, 1, "x", 1));
    assert(!elisa_ime_queue_push(&elisa_ime_commands, current_owner, 1, 1, "x", 1));
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 9, 1, NULL, 0));
    elisa_android_ime_drain();
    assert(delivered == delivered_before_close + ELISA_IME_QUEUE_CAPACITY - 2);
    assert(finishes == finishes_before_close + 1 && elisa_ime_consuming_batch == 0);
    assert(elisa_ime_commands.count == 0 && !elisa_ime_commands.batch_open);
    published_text = "";
    elisa_android_ime_publish_state(current_owner, 0, 0, 0);
    menu_request = current_owner;
    assert(elisa_android_ime_publish_state(current_owner, 0, 0, 0) == 1);
    snapshot = elisa_ime_connection_snapshot();
    uint64_t requested_serial = snapshot.menu_serial;
    assert(requested_serial != 0 && snapshot.start == snapshot.end);
    assert(elisa_android_ime_publish_state(current_owner, 0, 0, 0) == 0);
    assert(elisa_ime_connection_snapshot().menu_serial == requested_serial);
    menu_request = current_owner;
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 8, 0, NULL, 0));
    elisa_android_ime_drain();
    assert(elisa_android_ime_publish_state(current_owner, 0, 0, 0) == 0);
    assert(menu_request == current_owner);
    assert(elisa_ime_queue_push(&elisa_ime_commands, current_owner, 9, 0, NULL, 0));
    elisa_android_ime_drain();
    assert(elisa_android_ime_publish_state(current_owner, 0, 0, 0) == 1);
    assert(elisa_ime_connection_snapshot().menu_serial != requested_serial);
    menu_request = current_owner;
    ++current_owner;
    elisa_android_ime_publish_owner(current_owner);
    assert(elisa_ime_connection_snapshot().menu_serial == 0);
    elisa_android_ime_publish_state(current_owner, 0, 0, 0);
    assert(elisa_ime_connection_snapshot().menu_serial == 0);
    puts("android IME transport: all checks passed");
    return 0;
}
