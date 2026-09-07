/* Headless timing and memory harness for the Elisa-owned benchmark workload. */
#include <stdint.h>
#include <stdio.h>
#include <sys/resource.h>
#include <time.h>

extern void elisa_ui_benchmark_reset(void);
extern int32_t elisa_ui_benchmark_build(int32_t count);
extern void elisa_ui_benchmark_mutate(void);
extern void elisa_ui_benchmark_layout(void);
extern void elisa_ui_benchmark_paint(void);
extern void elisa_ui_benchmark_text(void);
extern int32_t elisa_ui_benchmark_widget_count(void);
extern int32_t elisa_ui_benchmark_command_count(void);

static uint64_t monotonic_ns(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return 0;
    return (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
}

static uint64_t elapsed_ns(uint64_t start, uint64_t finish) {
    return finish >= start ? finish - start : 0;
}

static uint64_t peak_rss_bytes(const struct rusage *usage) {
#if defined(__APPLE__)
    /* Darwin reports ru_maxrss in bytes; Linux and the BSDs report KiB. */
    return usage->ru_maxrss > 0 ? (uint64_t)usage->ru_maxrss : 0;
#else
    return usage->ru_maxrss > 0 ? (uint64_t)usage->ru_maxrss * UINT64_C(1024) : 0;
#endif
}

static uint64_t measure_first_frame(int iterations) {
    uint64_t start = monotonic_ns();
    for (int index = 0; index < iterations; ++index) {
        (void)elisa_ui_benchmark_build(64);
        elisa_ui_benchmark_paint();
    }
    return elapsed_ns(start, monotonic_ns());
}

static uint64_t measure_layout(int iterations) {
    (void)elisa_ui_benchmark_build(220);
    uint64_t start = monotonic_ns();
    for (int index = 0; index < iterations; ++index) {
        elisa_ui_benchmark_mutate();
        elisa_ui_benchmark_layout();
    }
    return elapsed_ns(start, monotonic_ns());
}

static uint64_t measure_paint(int iterations) {
    (void)elisa_ui_benchmark_build(220);
    uint64_t start = monotonic_ns();
    for (int index = 0; index < iterations; ++index) elisa_ui_benchmark_paint();
    return elapsed_ns(start, monotonic_ns());
}

static uint64_t measure_text(int iterations) {
    uint64_t start = monotonic_ns();
    for (int index = 0; index < iterations; ++index) elisa_ui_benchmark_text();
    return elapsed_ns(start, monotonic_ns());
}

int main(void) {
    const int iterations = 32;
    elisa_ui_benchmark_reset();
    if (elisa_ui_benchmark_build(220) != 221 ||
        elisa_ui_benchmark_widget_count() != 221) {
        puts("performance: large-tree capacity fixture failed");
        return 2;
    }
    elisa_ui_benchmark_paint();
    if (elisa_ui_benchmark_command_count() <= 220) {
        puts("performance: large-tree paint emitted too few commands");
        return 3;
    }

    /* Warm the compiler/runtime path before recording the reported samples. */
    (void)measure_first_frame(2);
    (void)measure_layout(2);
    (void)measure_paint(2);
    (void)measure_text(2);

    struct rusage before;
    struct rusage after;
    (void)getrusage(RUSAGE_SELF, &before);
    uint64_t first_frame_ns = measure_first_frame(iterations);
    uint64_t layout_ns = measure_layout(iterations);
    uint64_t paint_ns = measure_paint(iterations);
    uint64_t text_ns = measure_text(iterations);
    (void)getrusage(RUSAGE_SELF, &after);
    uint64_t before_rss_bytes = peak_rss_bytes(&before);
    uint64_t after_rss_bytes = peak_rss_bytes(&after);
    uint64_t peak_rss = after_rss_bytes > before_rss_bytes ? after_rss_bytes : before_rss_bytes;

    /* Generous CI ceilings catch accidental unbounded work without pretending
     * that a debug/O0 build is a product-performance claim. */
    const uint64_t first_frame_limit = UINT64_C(15000000000);
    const uint64_t phase_limit = UINT64_C(15000000000);
    if (first_frame_ns > first_frame_limit || layout_ns > phase_limit ||
        paint_ns > phase_limit || text_ns > phase_limit) {
        puts("performance: benchmark exceeded safety ceiling");
        return 4;
    }
    printf("performance: iterations=%d first_frame_ns=%llu layout_ns=%llu paint_ns=%llu text_ns=%llu large_tree_widgets=%d large_tree_commands=%d peak_rss_bytes=%llu\n",
           iterations, (unsigned long long)first_frame_ns,
           (unsigned long long)layout_ns, (unsigned long long)paint_ns,
           (unsigned long long)text_ns, elisa_ui_benchmark_widget_count(),
           elisa_ui_benchmark_command_count(), (unsigned long long)peak_rss);
    puts("performance: benchmark passed");
    return 0;
}
