/* What the Elisa runtime asks its host for that Android does not have.
 *
 * The runtime sizes its worker pool with sysctlbyname, which is a Darwin
 * call. Answering "no such name" makes it fall back to its own default,
 * which is the honest answer on a device whose core count it can read from
 * elsewhere if it ever needs to. */
#include <stddef.h>
#include <errno.h>

int sysctlbyname(const char *name, void *value, size_t *size, void *new_value, size_t new_size) {
    (void)name; (void)value; (void)size; (void)new_value; (void)new_size;
    errno = ENOENT;
    return -1;
}

/* The runtime prints a backtrace when it panics. Bionic has no execinfo;
 * a panic still aborts, it just says less. */
int backtrace(void **buffer, int size) {
    (void)buffer; (void)size;
    return 0;
}

void backtrace_symbols_fd(void *const *buffer, int size, int fd) {
    (void)buffer; (void)size; (void)fd;
}
