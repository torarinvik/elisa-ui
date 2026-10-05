/* End-to-end cold-miss versus warm-hit timing for the real SDL3 painter. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <time.h>

extern int32_t elisa_sdl3_text_cache_benchmark_setup(void);
extern void elisa_sdl3_text_cache_benchmark_paint(uint32_t color_variant);
extern void elisa_sdl3_text_cache_benchmark_clear(void);
extern void elisa_sdl3_text_cache_benchmark_teardown(void);
extern uintptr_t elisa_sdl3_text_cache_benchmark_count(void);
extern uint64_t elisa_sdl3_text_cache_benchmark_hits(void);
extern uint64_t elisa_sdl3_text_cache_benchmark_misses(void);

enum { SAMPLE_COUNT = 21, OPERATIONS_PER_SAMPLE = 256 };

static int monotonic_ns(uint64_t *result) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return 0;
    *result = (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
    return 1;
}

static void sort_samples(uint64_t *samples) {
    for (int index = 1; index < SAMPLE_COUNT; ++index) {
        uint64_t value = samples[index];
        int position = index;
        while (position > 0 && samples[position - 1] > value) {
            samples[position] = samples[position - 1];
            --position;
        }
        samples[position] = value;
    }
}

static int measure_cold_misses(uint64_t samples[SAMPLE_COUNT]) {
    for (int sample = 0; sample < SAMPLE_COUNT; ++sample) {
        elisa_sdl3_text_cache_benchmark_clear();
        uint64_t hits_before = elisa_sdl3_text_cache_benchmark_hits();
        uint64_t misses_before = elisa_sdl3_text_cache_benchmark_misses();
        uint64_t start = 0;
        uint64_t finish = 0;
        if (!monotonic_ns(&start)) return 0;
        uint32_t first_variant = (uint32_t)(sample * OPERATIONS_PER_SAMPLE);
        for (int index = 0; index < OPERATIONS_PER_SAMPLE; ++index) {
            elisa_sdl3_text_cache_benchmark_paint(first_variant + (uint32_t)index);
        }
        if (!monotonic_ns(&finish) || finish <= start) return 0;
        if (elisa_sdl3_text_cache_benchmark_hits() != hits_before ||
            elisa_sdl3_text_cache_benchmark_misses() - misses_before != OPERATIONS_PER_SAMPLE ||
            elisa_sdl3_text_cache_benchmark_count() > 32) return 0;
        samples[sample] = (finish - start) / OPERATIONS_PER_SAMPLE;
    }
    return 1;
}

static int measure_warm_hits(uint64_t samples[SAMPLE_COUNT]) {
    for (int sample = 0; sample < SAMPLE_COUNT; ++sample) {
        elisa_sdl3_text_cache_benchmark_clear();
        elisa_sdl3_text_cache_benchmark_paint(UINT32_C(1000));
        uint64_t hits_before = elisa_sdl3_text_cache_benchmark_hits();
        uint64_t misses_before = elisa_sdl3_text_cache_benchmark_misses();
        uint64_t start = 0;
        uint64_t finish = 0;
        if (!monotonic_ns(&start)) return 0;
        for (int index = 0; index < OPERATIONS_PER_SAMPLE; ++index) {
            elisa_sdl3_text_cache_benchmark_paint(UINT32_C(1000));
        }
        if (!monotonic_ns(&finish) || finish <= start) return 0;
        if (elisa_sdl3_text_cache_benchmark_hits() - hits_before != OPERATIONS_PER_SAMPLE ||
            elisa_sdl3_text_cache_benchmark_misses() != misses_before ||
            elisa_sdl3_text_cache_benchmark_count() != 1) return 0;
        samples[sample] = (finish - start) / OPERATIONS_PER_SAMPLE;
    }
    return 1;
}

static void print_samples(const char *name, const uint64_t values[SAMPLE_COUNT]) {
    printf("\"%s\":[", name);
    for (int index = 0; index < SAMPLE_COUNT; ++index) {
        printf("%s%llu", index == 0 ? "" : ",", (unsigned long long)values[index]);
    }
    putchar(']');
}

int main(void) {
    int32_t setup_status = elisa_sdl3_text_cache_benchmark_setup();
    if (setup_status != 0) {
        fprintf(stderr, "sdl3 text cache benchmark: setup failed at stage %d\n", setup_status);
        return 2;
    }

    /* Resolve the font and warm SDL's renderer before timed samples. */
    elisa_sdl3_text_cache_benchmark_paint(UINT32_C(1000));
    elisa_sdl3_text_cache_benchmark_clear();
    for (int index = 0; index < OPERATIONS_PER_SAMPLE; ++index) {
        elisa_sdl3_text_cache_benchmark_paint((uint32_t)index);
    }
    elisa_sdl3_text_cache_benchmark_clear();
    elisa_sdl3_text_cache_benchmark_paint(UINT32_C(1000));
    for (int index = 0; index < 16; ++index) {
        elisa_sdl3_text_cache_benchmark_paint(UINT32_C(1000));
    }
    uint64_t cold[SAMPLE_COUNT] = {0};
    uint64_t warm[SAMPLE_COUNT] = {0};
    int ok = measure_cold_misses(cold) && measure_warm_hits(warm);
    if (!ok) {
        fprintf(stderr, "sdl3 text cache benchmark: cache counters or clock failed\n");
        elisa_sdl3_text_cache_benchmark_teardown();
        return 3;
    }

    uint64_t cold_sorted[SAMPLE_COUNT];
    uint64_t warm_sorted[SAMPLE_COUNT];
    for (int index = 0; index < SAMPLE_COUNT; ++index) {
        cold_sorted[index] = cold[index];
        warm_sorted[index] = warm[index];
    }
    sort_samples(cold_sorted);
    sort_samples(warm_sorted);
    uint64_t cold_median = cold_sorted[SAMPLE_COUNT / 2];
    uint64_t warm_median = warm_sorted[SAMPLE_COUNT / 2];
    double speedup = warm_median > 0 ? (double)cold_median / (double)warm_median : 0.0;
    if (warm_median == 0 || cold_median <= warm_median) {
        fprintf(stderr, "sdl3 text cache benchmark: warm median did not beat cold misses\n");
        elisa_sdl3_text_cache_benchmark_teardown();
        return 4;
    }

    printf("{\"workload\":\"sdl3-text-cache-full-painter\",\"operations_per_sample\":%d,\"samples\":{", OPERATIONS_PER_SAMPLE);
    print_samples("cold_miss_ns_per_draw", cold);
    putchar(',');
    print_samples("warm_hit_ns_per_draw", warm);
    printf("},\"median_ns_per_draw\":{\"cold_miss\":%llu,\"warm_hit\":%llu},\"speedup\":%.2fx}\n",
           (unsigned long long)cold_median, (unsigned long long)warm_median, speedup);
    elisa_sdl3_text_cache_benchmark_teardown();
    return 0;
}
