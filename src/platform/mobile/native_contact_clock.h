#ifndef ELISA_UI_NATIVE_CONTACT_CLOCK_H
#define ELISA_UI_NATIVE_CONTACT_CLOCK_H
#include <math.h>
#include <stdbool.h>

/* Preserve subsecond thresholds even after months of system uptime. All
 * contacts in one stream share an origin; only a new primary down resets it.
 * Subtract in native precision before narrowing the portable record to float. */
typedef struct {
    double origin;
    bool initialized;
} elisa_contact_clock;

static inline float elisa_contact_seconds(elisa_contact_clock *clock,
                                         double native_seconds, bool new_stream) {
    if (!isfinite(native_seconds) || native_seconds < 0.0) return NAN;
    if (new_stream || !clock->initialized) {
        clock->origin = native_seconds;
        clock->initialized = true;
    }
    const double elapsed = native_seconds - clock->origin;
    return elapsed < 0.0 ? NAN : (float)elapsed;
}
#endif
