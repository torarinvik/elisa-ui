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
extern void elisa_ui_benchmark_prepare_text(void);
extern void elisa_ui_benchmark_text_input(void);
extern void elisa_ui_benchmark_prepare_virtual_list(void);
extern int32_t elisa_ui_benchmark_virtual_list_window(void);
extern int32_t elisa_ui_benchmark_widget_count(void);
extern int32_t elisa_ui_benchmark_command_count(void);

enum { ITERATIONS = 32, WARMUP_ITERATIONS = 2, SAMPLE_REPETITIONS = 7 };
typedef int (*measure_phase_fn)(int iterations, uint64_t *elapsed);

typedef struct {
    uint64_t sample_ns[SAMPLE_REPETITIONS];
    uint64_t median_ns;
    uint64_t maximum_ns;
} phase_samples;

static int monotonic_ns(uint64_t *result) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return 0;
    *result = (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
    return 1;
}

static int elapsed_ns(uint64_t start, uint64_t *elapsed) {
    uint64_t finish = 0;
    if (!monotonic_ns(&finish) || finish < start) return 0;
    *elapsed = finish - start;
    return *elapsed > 0;
}

static uint64_t peak_rss_bytes(const struct rusage *usage) {
#if defined(__APPLE__)
    /* Darwin reports ru_maxrss in bytes; Linux and the BSDs report KiB. */
    return usage->ru_maxrss > 0 ? (uint64_t)usage->ru_maxrss : 0;
#else
    return usage->ru_maxrss > 0 ? (uint64_t)usage->ru_maxrss * UINT64_C(1024) : 0;
#endif
}

static int measure_first_frame(int iterations, uint64_t *elapsed) {
    uint64_t start = 0;
    if (!monotonic_ns(&start)) return 0;
    for (int index = 0; index < iterations; ++index) {
        (void)elisa_ui_benchmark_build(64);
        elisa_ui_benchmark_paint();
    }
    return elapsed_ns(start, elapsed);
}

static int measure_layout(int iterations, uint64_t *elapsed) {
    (void)elisa_ui_benchmark_build(220);
    uint64_t start = 0;
    if (!monotonic_ns(&start)) return 0;
    for (int index = 0; index < iterations; ++index) {
        elisa_ui_benchmark_mutate();
        elisa_ui_benchmark_layout();
    }
    return elapsed_ns(start, elapsed);
}

static int measure_paint(int iterations, uint64_t *elapsed) {
    (void)elisa_ui_benchmark_build(220);
    uint64_t start = 0;
    if (!monotonic_ns(&start)) return 0;
    for (int index = 0; index < iterations; ++index) elisa_ui_benchmark_paint();
    return elapsed_ns(start, elapsed);
}

static int measure_text(int iterations, uint64_t *elapsed) {
    uint64_t start = 0;
    if (!monotonic_ns(&start)) return 0;
    for (int index = 0; index < iterations; ++index) elisa_ui_benchmark_text();
    return elapsed_ns(start, elapsed);
}

static int measure_text_input(int iterations, uint64_t *elapsed) {
    elisa_ui_benchmark_prepare_text();
    uint64_t start = 0;
    if (!monotonic_ns(&start)) return 0;
    for (int index = 0; index < iterations; ++index) elisa_ui_benchmark_text_input();
    return elapsed_ns(start, elapsed);
}

static int measure_virtual_list_window(int iterations, uint64_t *elapsed) {
    elisa_ui_benchmark_prepare_virtual_list();
    uint64_t start = 0;
    if (!monotonic_ns(&start)) return 0;
    for (int index = 0; index < iterations; ++index) {
        if (elisa_ui_benchmark_virtual_list_window() != 4) return 0;
    }
    return elapsed_ns(start, elapsed);
}

static int measure_samples(measure_phase_fn phase, phase_samples *result) {
    *result = (phase_samples){0};
    uint64_t sorted[SAMPLE_REPETITIONS];
    for (int index = 0; index < SAMPLE_REPETITIONS; ++index) {
        uint64_t elapsed = 0;
        if (!phase(ITERATIONS, &elapsed) || elapsed == 0) return 0;
        result->sample_ns[index] = elapsed;
        sorted[index] = elapsed;
    }
    for (int index = 1; index < SAMPLE_REPETITIONS; ++index) {
        uint64_t value = sorted[index];
        int position = index;
        while (position > 0 && sorted[position - 1] > value) {
            sorted[position] = sorted[position - 1];
            --position;
        }
        sorted[position] = value;
    }
    result->median_ns = sorted[SAMPLE_REPETITIONS / 2];
    result->maximum_ns = sorted[SAMPLE_REPETITIONS - 1];
    return 1;
}

static void print_phase(const char *name, const phase_samples *phase, uint64_t operations) {
    printf("\"%s\":{\"samples_ns\":[", name);
    for (int index = 0; index < SAMPLE_REPETITIONS; ++index) {
        printf("%s%llu", index == 0 ? "" : ",", (unsigned long long)phase->sample_ns[index]);
    }
    printf("],\"operations_per_batch\":%llu,\"median_batch_ns\":%llu,\"max_sample_ns\":%llu,\"median_operation_ns\":%llu}",
           (unsigned long long)operations,
           (unsigned long long)phase->median_ns,
           (unsigned long long)phase->maximum_ns,
           (unsigned long long)(operations > 0 ? phase->median_ns / operations : 0));
}

int main(void) {
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
    const int large_tree_widgets = elisa_ui_benchmark_widget_count();
    const int large_tree_commands = elisa_ui_benchmark_command_count();

    /* Warm the compiler/runtime path before recording the reported samples. */
    uint64_t warmup_elapsed = 0;
    if (!measure_first_frame(WARMUP_ITERATIONS, &warmup_elapsed) ||
        !measure_layout(WARMUP_ITERATIONS, &warmup_elapsed) ||
        !measure_paint(WARMUP_ITERATIONS, &warmup_elapsed) ||
        !measure_text(WARMUP_ITERATIONS, &warmup_elapsed) ||
        !measure_text_input(WARMUP_ITERATIONS, &warmup_elapsed) ||
        !measure_virtual_list_window(WARMUP_ITERATIONS, &warmup_elapsed)) {
        puts("performance: monotonic clock failed during warmup");
        return 5;
    }

    struct rusage before = {0};
    struct rusage after = {0};
    if (getrusage(RUSAGE_SELF, &before) != 0) {
        puts("performance: could not read process resource usage");
        return 6;
    }
    phase_samples first_frame = {0};
    phase_samples layout = {0};
    phase_samples paint = {0};
    phase_samples text = {0};
    phase_samples text_input = {0};
    phase_samples virtual_list_window = {0};
    if (!measure_samples(measure_first_frame, &first_frame) ||
        !measure_samples(measure_layout, &layout) ||
        !measure_samples(measure_paint, &paint) ||
        !measure_samples(measure_text, &text) ||
        !measure_samples(measure_text_input, &text_input) ||
        !measure_samples(measure_virtual_list_window, &virtual_list_window)) {
        puts("performance: monotonic clock failed while sampling");
        return 5;
    }
    if (getrusage(RUSAGE_SELF, &after) != 0) {
        puts("performance: could not read process resource usage");
        return 6;
    }
    uint64_t before_rss_bytes = peak_rss_bytes(&before);
    uint64_t after_rss_bytes = peak_rss_bytes(&after);
    uint64_t peak_rss = after_rss_bytes > before_rss_bytes ? after_rss_bytes : before_rss_bytes;
    if (peak_rss == 0) {
        puts("performance: process peak RSS was unavailable");
        return 6;
    }

    /* Generic runaway-work safety limits are not product-performance budgets. */
    const uint64_t phase_limit = UINT64_C(15000000000);
    if (first_frame.maximum_ns > phase_limit || layout.maximum_ns > phase_limit ||
        paint.maximum_ns > phase_limit || text.maximum_ns > phase_limit ||
        text_input.maximum_ns > phase_limit || virtual_list_window.maximum_ns > phase_limit) {
        puts("performance: benchmark exceeded safety ceiling");
        return 4;
    }

    printf("{\"schema_version\":1,\"workload_id\":\"retained-tree-v3-large-list\",\"iterations\":%d,\"warmups\":%d,\"repetitions\":%d,\"large_tree_widgets\":%d,\"large_tree_commands\":%d,\"peak_rss_bytes\":%llu,\"phases\":{",
           ITERATIONS, WARMUP_ITERATIONS, SAMPLE_REPETITIONS,
           large_tree_widgets, large_tree_commands, (unsigned long long)peak_rss);
    print_phase("first_frame", &first_frame, ITERATIONS);
    putchar(',');
    print_phase("layout", &layout, ITERATIONS);
    putchar(',');
    print_phase("paint", &paint, ITERATIONS);
    putchar(',');
    print_phase("text", &text, ITERATIONS * 64);
    putchar(',');
    print_phase("text_input", &text_input, ITERATIONS * 16);
    putchar(',');
    print_phase("virtual_list_window", &virtual_list_window, ITERATIONS * 4);
    puts("}}");
    puts("performance: benchmark passed");
    return 0;
}
