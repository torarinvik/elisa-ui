# UI performance gate

`test/performance_benchmark.elisa` is a deterministic, headless workload for
the retained Elisa framework. Its C companion only supplies a monotonic clock,
process RSS sampling, and a safety gate; it does not build widgets or replay
commands itself. This keeps the measured work inside the same layout, paint,
semantic, text, and editing modules used by applications.

Run it without opening a native window:

```sh
ELISA_UI_STAGE1=../Elisa-compiler ELISA_UI_REQUIRE_PERF_BUDGET=1 bash scripts/check_performance.sh
```

The script compiles the fixture with the current stage1 product at `-O2`,
links the checked-in Elisa runtime, and reports nanoseconds for six phases.
It launches three independent benchmark processes by default; each process
warms each phase twice and records seven measured batches of 32 iterations.
The result includes every batch duration, the median and maximum across all
21 batches, per-operation median, and process peak RSS. A versioned workload
ID and hashes for the workload sources, including both virtual-list modules,
prevent a changed fixture from silently reusing an old threshold. The tuple
also records the exact stage1/runtime and Clang binary hashes, host identity,
all compile/link flags, and per-phase operation counts.

- first frame: build 64 retained rows and paint, repeated 32 times;
- relayout: mutate a retained margin and arrange a 221-node tree, repeated 32
  times;
- paint: replay the same large tree, repeated 32 times;
- text: perform 64 bounded Unicode-aware line layouts per iteration, repeated
  32 times.
- text input: focus a retained field and commit a UTF-8 `é👋` sequence 16 times
  per iteration, repeated 32 times (including edit-history bookkeeping).
- virtual-list window: calculate, realize, map, position, and project semantic
  rows at the start, former f32 saturation boundary, midpoint, and tail of a
  16,777,216-item list (128 bounded windows per 32-iteration batch).

Typography queries are cached in Elisa for the duration of each paint. The
bounded `UiTextMetrics` table removes repeated line-height and caption/range
width FFI calls; copied width keys and the paint/tree-boundary reset keep cache
memory bounded and prevent a new font or scale from reusing an old metric.
The Skia custom adapter applies the same principle to grapheme-width queries
with a separate bounded byte-keyed table, invalidated on scale or borrowed
binding reset and bypassed for oversized clusters.
Skia image and font bindings use a slot-indexed Elisa reverse map with an
exact-generation check, so bound draw and metric queries do not scan the full
binding tables. Cleanup remains a bounded table sweep at lifecycle boundaries.

The large-tree assertion verifies 221 retained widgets and at least one paint
command per widget; its semantic pass also exercises the Elisa-owned ID index.
`test/stress_test.elisa` adds a separate bounded-safety pass: 50 start/stop
sessions, resource-capacity overflow, owner disposal, a 5,000-event burst where
an authoritative quit still lands, command-capacity overflow, and hostile
non-finite geometry. It asserts bounded counts and diagnostics rather than
timings.
`peak_rss_bytes` is the process high-water mark (Darwin's
`ru_maxrss` is already bytes; platforms that report KiB are normalized by the
harness). The 15-second per-phase ceilings are intentionally generous safety
limits for CI and catch accidental unbounded work; they are not product-frame
budgets or cross-machine performance claims.

`test/performance_budgets.json` holds measured reference-device thresholds.
The newest entry (2026-10-05) is macOS 27.0.1 build 26A434 on Mac17,4 / Apple
M5, using Homebrew clang 23.1.1 and Stage1 revision `8e08cd33` (product SHA-256
`f7d4dc3c…e19b9d`, runtime SHA-256 `b51e6114…bd11897`). It records all 21
raw samples per phase, verified median/maximum/RSS, and separate median and
outlier limits: 4.208 ms first-frame batches, 2.108 ms layout, 6.382 ms
paint, 24.084 ms text, 0.621 ms text input, 0.087 ms per 128 virtual-list
windows, and 4,014,080 bytes peak RSS. The required exact-tuple gate passes on
a fresh repeat run; see the [dated validation note](implementation-baseline/validation-2026-10-05.md).
A budget matches only the exact OS, device, compiler
product/runtime, Clang binary, workload version/counts/flags, and workload
source hashes. No other device inherits the M5 thresholds. Without an exact
match the default mode prints `UNBUDGETED` and keeps only the generic safety
ceiling; `ELISA_UI_REQUIRE_PERF_BUDGET=1` fails instead of treating that as a
budget pass. The acceptance suite sets this flag, so an unknown device,
compiler, or workload cannot pass `run_tests.sh` without its own measured entry.
For exploratory data collection on an unbaselined machine, run the script with
`ELISA_UI_REQUIRE_PERF_BUDGET=0`; that is not an acceptance pass. Add a
reference entry only after collecting repeated samples on that device and
recording its complete metadata.

## SDL3 retained text cache

`bash scripts/bench_sdl3_text_cache.sh` measures the full SDL3 paint path on a
dummy-video window, including `UiCore::begin_frame`, command recording,
`UiPaint::replay`, and `SDL_RenderPresent`. Each process records 21 samples of
256 draws. The cold-miss phase uses the same text and size with varying colors
to force misses and LRU replacement; the warm-hit phase primes one exact key
and repeats it. The C harness verifies miss/hit counters and the cache-entry
bound before accepting timing data. It reports every sample and the median
nanoseconds per draw; this is a focused cache datapoint, not a reference-device
acceptance budget.

Three process runs on macOS 27.0.1 build 26A434, Mac17,4 / Apple M5, Stage1
`8e08cd33` (product SHA-256
`78a26e2c5142c84fc2fe6769281a445621ed10f13d750545ea26dd8e490e50d5`),
Homebrew SDL3 3.4.16 and SDL_ttf 3.2.2 measured cold/warm medians of
32,015/4,648 ns, 24,324/3,535 ns, and 24,078/3,441 ns per draw. The median of
the three process medians is 24,324 ns versus 3,535 ns (6.88×). The exact
samples and interpretation are preserved in the [dated validation note](implementation-baseline/validation-2026-10-05.md).

## Skia simple-text fallback cache

`src/platform/skia/skia_simple_text_cache.inc` adds a shared bounded LRU for
Skia's simple-text fallback: 64 entries, 1 MiB estimated total, and 64 KiB per
entry. It retains per-fallback-run `SkTextBlob`s and measured advances, keyed
by exact counted UTF-8, `SkFont`, typeface identity, font-manager identity,
locale revision, and scale generation. Paint and draw origin remain outside
the key. Font-manager, text-quality, locale/scale, explicit cache-clear, and
surface-loss paths invalidate it. Tracked text bypasses the cache so its
per-scalar tracking behavior is unchanged.

The real Apple CPU-raster gate verifies cache reuse and exact pixel parity
against the previous split-run `drawSimpleText` path at a fractional origin,
for a plain run under two paint colors and for a separate fallback-font run.
It also checks exact
text/font/typeface key separation, locale/scale, font-manager and text-quality
invalidation, entry- and byte-cost LRU limits, oversized-text bypass, and
surface-loss clearing. The
Android ARM64 NDK compiles the real text shim with warnings-as-errors. This is
correctness/build evidence only; no Skia-cache speedup is claimed. A full
Android application build currently stops earlier in generated profiler
fallback C at the NDK 30 `va_copy`/`va_end` macro boundary, and no Android
device was attached for runtime acceptance.

This gate measures CPU-side framework work and process peak RSS; it does not
count allocations. It does not claim GPU upload latency, display-vsync pacing,
battery/energy use, mobile thermal behavior, or hosted transport cost. Those require a real Skia GPU
surface, device hosts, or WasmBrowser/remote transport fixtures and remain
separate validation work.

## WasmBrowser presentation payload baseline

`scripts/check_wasmbrowser_transfer.sh` runs the production `UiWasmBrowser`
encoder against C host stubs and inspects the callback arguments. Its focused
fixture emits all seven current command tags and verifies their payloads,
including image slot/generation, alpha, corner, and fit; the frame exposes a
224-byte span (seven 32-byte records). A semantic snapshot is 137 bytes for
one node with 9 text bytes, and 33,800 bytes for 256 nodes using the full 3-KiB
aggregate text budget. The maximum case verifies the last record and last text
range as well as the version/count header.

The guest reuses its command and semantic arrays; the native fixture verifies
the callback pointer for each stays identical across its two frames. Text
commands carry borrowed guest-memory pointer/length pairs rather than copying
their text into the 32-byte record; semantic strings are copied into the
reusable snapshot. The
semantic array is now sized to its reachable maximum, 33,800 bytes, down from
125,952 bytes (92,152 fewer statically reserved bytes). The fixture measures
the logical spans presented to imports and validates the bound; it does not
exercise the real component host or SDK-owned typed bindings, nor measure a
host-side clone, network/remote transport, or elapsed transfer time.

## Required renderer evidence

The portable benchmark is not a substitute for raster proof. The default
`scripts/run_tests.sh` gate now requires `scripts/check_skia.sh`, which in turn
requires the exact checkout and CPU-raster archive pinned by
`third_party/skia.lock`. `scripts/check_skia_offscreen.sh` renders the real
Elisa painter into a headless SkSurface, verifies pixels and text, and repeats
the complete frame through the same public export. Its output includes
`render_iterations`, `render_total_ns`, and `render_average_ns`, providing a
reproducible CPU-rendering datapoint alongside the retained-tree timings.
The renderer scripts accept only an explicit integer iteration count in
`1..10000`; malformed values fail before timing starts instead of silently
changing the sample size.
The host rejects a zero-duration sample, checks rasterized title ink, and
compares a logical-pixel digest before and after repeated replays. The required
shell gate then launches each real host a second time and compares that digest
across fresh processes. A nominally successful call therefore cannot satisfy
the gate without producing measured, stable pixels; leaked save/clip/transform
state is caught as a digest change, and process-global initialization cannot
hide nondeterministic output.
The same required gate then runs `scripts/check_showcase_skia.sh`: it drives
the shipped `examples/hello/app.elisa` public callbacks (focus, UTF-8/IME
editing, validation, state save/restore, and resource replacement) and verifies that the
resulting retained custom artwork produces real accent pixels in an 800x680
SkSurface. The fixture binds a host-decoded image, proves the stale resource
generation is skipped, and proves the replacement generation is painted before
the repeated timing loop; the shell gate repeats the entire workflow in a fresh
process and requires the same logical pixel digest. Its output adds command,
semantic, artwork-pixel, resource-generation, edited-text-ink, frame timing, and
replay-digest evidence. The edited-text check also requires a grapheme-safe
selection surface inside the field. The generic and Skia showcase workflows
also drive an invalid-to-valid project-name edit through the public validation
view, and the Skia host requires ink from its final status label, so a passing
renderer check demonstrates an application workflow rather than only isolated
primitive calls.

The AppKit/CoreGraphics fallback is also checked headlessly by
`scripts/check_appkit_canvas.sh`; it renders the 800x680 smoke frame in two
fresh processes and compares the PNG SHA-256 before running its semantic bridge
fixture. This keeps the native fallback reproducible without opening or
activating a window.
The AppKit/Skia compositor fixture applies the same repeated-frame digest and
positive-duration check to its borrowed CoreGraphics presentation surface.

The only supported local escape hatch is explicit and non-passing:
`ELISA_UI_REQUIRE_REAL_SKIA=0`. The gate rejects any other value, so a typo
cannot silently disable the required renderer check. The opt-out is useful
while editing Elisa code on a machine without the pinned SDK, but CI and
release checks must leave it unset.
