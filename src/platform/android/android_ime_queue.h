#ifndef ELISA_ANDROID_IME_QUEUE_H
#define ELISA_ANDROID_IME_QUEUE_H

#include <pthread.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

// Raw transport only: the owner thread publishes an opaque document/session
// identity. Producers must carry that identity, never resolve retained state.
#define ELISA_IME_QUEUE_CAPACITY 16
#define ELISA_IME_QUEUE_BYTES 1024
typedef struct {
    uint64_t owner;
    int32_t kind; // 0 compose, 1 commit, 2 report, 3 finish, 4 select, 5 UTF16 delete, 6 scalar delete, 7 mark
    // 8 outer batch begin, 9 outer batch end, 10 retained context action
    int32_t cursor;
    size_t length;
    unsigned char bytes[ELISA_IME_QUEUE_BYTES];
} elisa_ime_command;
typedef struct {
    pthread_mutex_t mutex;
    uint64_t owner;
    size_t head, count;
    int batch_open;
    elisa_ime_command commands[ELISA_IME_QUEUE_CAPACITY];
} elisa_ime_queue;
#define ELISA_IME_QUEUE_INITIALIZER {PTHREAD_MUTEX_INITIALIZER, 0, 0, 0, 0, {{0, 0, 0, 0, {0}}}}

static inline void elisa_ime_queue_scrub(void *memory, size_t length) {
    volatile unsigned char *bytes = (volatile unsigned char *)memory;
    while (length--) *bytes++ = 0;
}

// Caller holds mutex; shared by coherent owner/traits publication.
static inline void elisa_ime_queue_owner_locked(elisa_ime_queue *queue, uint64_t owner) {
    if (queue->owner != owner) {
        elisa_ime_queue_scrub(queue->commands, sizeof(queue->commands));
        queue->head = queue->count = 0;
        queue->batch_open = 0;
        queue->owner = owner;
    }
}
static inline void elisa_ime_queue_owner(elisa_ime_queue *queue, uint64_t owner) {
    pthread_mutex_lock(&queue->mutex);
    elisa_ime_queue_owner_locked(queue, owner);
    pthread_mutex_unlock(&queue->mutex);
}

static inline int elisa_ime_queue_push(elisa_ime_queue *queue, uint64_t owner,
        int32_t kind, int32_t cursor, const void *bytes, size_t length) {
    // 8/9 delimit only outer batches. Nested depth belongs to the connection.
    if (!owner || kind < 0 || kind > 10 || length > ELISA_IME_QUEUE_BYTES ||
        (length && !bytes)) return 0;
    if ((kind == 8 || kind == 9) && length != 0) return 0;
    if (kind == 10 && (length != 0 || cursor < 1 || cursor > 4)) return 0;
    pthread_mutex_lock(&queue->mutex);
    size_t room = ELISA_IME_QUEUE_CAPACITY - (queue->batch_open ? 1 : 0);
    int accepted = queue->owner == owner && queue->count < room;
    if (kind == 8) accepted = queue->owner == owner && !queue->batch_open && queue->count < ELISA_IME_QUEUE_CAPACITY - 1;
    if (kind == 9) accepted = queue->owner == owner && queue->batch_open && queue->count < ELISA_IME_QUEUE_CAPACITY;
    if (accepted) {
        size_t slot = (queue->head + queue->count) % ELISA_IME_QUEUE_CAPACITY;
        elisa_ime_command *command = &queue->commands[slot];
        command->owner = owner;
        command->kind = kind;
        command->cursor = cursor;
        command->length = length;
        if (length) memcpy(command->bytes, bytes, length);
        ++queue->count;
        if (kind == 8) queue->batch_open = 1;
        if (kind == 9) queue->batch_open = 0;
    }
    pthread_mutex_unlock(&queue->mutex);
    return accepted; // Full means rejected, never a silently overwritten edit.
}

static inline int elisa_ime_queue_pop(elisa_ime_queue *queue, elisa_ime_command *out) {
    if (!out) return 0;
    pthread_mutex_lock(&queue->mutex);
    int available = queue->count != 0;
    if (available) {
        *out = queue->commands[queue->head];
        elisa_ime_queue_scrub(&queue->commands[queue->head], sizeof(*out));
        queue->head = (queue->head + 1) % ELISA_IME_QUEUE_CAPACITY;
        --queue->count;
    }
    pthread_mutex_unlock(&queue->mutex);
    return available;
}
#endif
