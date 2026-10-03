#include "../src/platform/android/android_ime_queue.h"
#include <cassert>
#include <thread>
#include <cstdio>

int main() {
    elisa_ime_queue queue = ELISA_IME_QUEUE_INITIALIZER;
    assert(!elisa_ime_queue_push(&queue, 1, 1, 1, "x", 1));
    elisa_ime_queue_owner(&queue, 1);
    assert(!elisa_ime_queue_push(&queue, 2, 1, 1, "x", 1));
    assert(!elisa_ime_queue_push(&queue, 1, 10, 1, "x", 1));
    assert(!elisa_ime_queue_push(&queue, 1, 1, 1, nullptr, 1));
    for (int i = 0; i < ELISA_IME_QUEUE_CAPACITY; ++i)
        assert(elisa_ime_queue_push(&queue, 1, i % 2, i, "secret", 6));
    assert(!elisa_ime_queue_push(&queue, 1, 1, 99, "x", 1));
    elisa_ime_command command{};
    for (int i = 0; i < ELISA_IME_QUEUE_CAPACITY; ++i) {
        assert(elisa_ime_queue_pop(&queue, &command));
        assert(command.cursor == i && command.kind == i % 2 && command.length == 6);
        for (unsigned char byte : queue.commands[i].bytes) assert(byte == 0);
        elisa_ime_queue_scrub(&command, sizeof(command));
    }
    assert(!elisa_ime_queue_pop(&queue, &command));
    assert(elisa_ime_queue_push(&queue, 1, 0, 0, "secret", 6));
    elisa_ime_queue_owner(&queue, 2);
    assert(!elisa_ime_queue_pop(&queue, &command));
    for (const auto &slot : queue.commands)
        for (unsigned char byte : slot.bytes) assert(byte == 0);
    assert(!elisa_ime_queue_push(&queue, 1, 1, 1, "old", 3));
    std::thread producer([&] {
        for (int i = 0; i < 10000; ++i)
            while (!elisa_ime_queue_push(&queue, 2, 1, i, "x", 1)) std::this_thread::yield();
    });
    for (int i = 0; i < 10000; ++i) {
        while (!elisa_ime_queue_pop(&queue, &command)) std::this_thread::yield();
        assert(command.owner == 2 && command.cursor == i && command.bytes[0] == 'x');
        elisa_ime_queue_scrub(&command, sizeof(command));
    }
    producer.join();
    assert(!elisa_ime_queue_push(&queue, 2, 9, 0, nullptr, 0));
    assert(elisa_ime_queue_push(&queue, 2, 8, 0, nullptr, 0));
    assert(!elisa_ime_queue_push(&queue, 2, 8, 0, nullptr, 0));
    for (int i = 0; i < ELISA_IME_QUEUE_CAPACITY - 2; ++i)
        assert(elisa_ime_queue_push(&queue, 2, 1, i, "x", 1));
    assert(!elisa_ime_queue_push(&queue, 2, 1, 99, "overflow", 8));
    assert(elisa_ime_queue_push(&queue, 2, 9, 0, nullptr, 0));
    assert(queue.count == ELISA_IME_QUEUE_CAPACITY && !queue.batch_open);
    assert(elisa_ime_queue_pop(&queue, &command) && command.kind == 8);
    for (int i = 0; i < ELISA_IME_QUEUE_CAPACITY - 2; ++i)
        assert(elisa_ime_queue_pop(&queue, &command) && command.kind == 1 && command.cursor == i);
    assert(elisa_ime_queue_pop(&queue, &command) && command.kind == 9);
    assert(elisa_ime_queue_push(&queue, 2, 8, 0, nullptr, 0));
    elisa_ime_queue_owner(&queue, 3);
    assert(!queue.batch_open && queue.count == 0);
    assert(!elisa_ime_queue_push(&queue, 2, 9, 0, nullptr, 0));
    assert(!elisa_ime_queue_push(&queue, 3, 8, 0, "x", 1));
    for (int i = 0; i < ELISA_IME_QUEUE_CAPACITY - 1; ++i)
        assert(elisa_ime_queue_push(&queue, 3, 1, 0, "x", 1));
    assert(!elisa_ime_queue_push(&queue, 3, 8, 0, nullptr, 0));
    elisa_ime_queue_owner(&queue, 0);
    assert(!elisa_ime_queue_push(&queue, 2, 1, 1, "late", 4));
    pthread_mutex_destroy(&queue.mutex);
    std::puts("android IME queue: all checks passed");
}
