#include "../src/platform/android/android_ime_queue.h"
#include <assert.h>

int main(void) {
    elisa_ime_queue queue = ELISA_IME_QUEUE_INITIALIZER;
    elisa_ime_command command;
    elisa_ime_queue_owner(&queue, 7);
    assert(elisa_ime_queue_push(&queue, 7, 0, -1, NULL, 0));
    assert(elisa_ime_queue_pop(&queue, &command));
    assert(command.owner == 7 && command.cursor == -1 && command.length == 0);
    elisa_ime_queue_scrub(&command, sizeof(command));
    elisa_ime_queue_owner(&queue, 0);
    pthread_mutex_destroy(&queue.mutex);
    return 0;
}
