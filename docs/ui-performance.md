# UI performance gate

`test/performance_benchmark.elisa` is a deterministic, headless workload for
the retained Elisa framework. Its C companion only supplies a monotonic clock,
process RSS sampling, and a safety gate; it does not build widgets or replay
commands itself. This keeps the measured work inside the same layout, paint,
semantic, text, and editing modules used by applications.

Run it without opening a native window:

```sh
ELISA_UI_STAGE1=../wasm-sdk-compiler bash scripts/check_performance.sh
```

The script compiles the fixture with the current stage1 product at `-O2`,
links the checked-in Elisa runtime, and reports nanoseconds for five phases:

- first frame: build 64 retained rows and paint, repeated 32 times;
- relayout: mutate a retained margin and arrange a 221-node tree, repeated 32
  times;
- paint: replay the same large tree, repeated 32 times;
- text: perform 64 bounded Unicode-aware line layouts per iteration, repeated
  32 times.
- text input: focus a retained field and commit a UTF-8 `é👋` sequence 16 times
  per iteration, repeated 32 times (including edit-history bookkeeping).

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
`peak_rss_bytes` is the process high-water mark (Darwin's
`ru_maxrss` is already bytes; platforms that report KiB are normalized by the
harness). The 15-second per-phase ceilings are intentionally generous safety
limits for CI and catch accidental unbounded work; they are not product-frame
budgets or cross-machine performance claims.

This gate measures CPU-side framework work and retained memory only. It does
not claim GPU upload latency, display-vsync pacing, battery/energy use, mobile
thermal behavior, or hosted transport cost. Those require a real Skia GPU
surface, device hosts, or WasmBrowser/remote transport fixtures and remain
separate validation work.

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
