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

The large-tree assertion verifies 221 retained widgets and at least one paint
command per widget. `peak_rss_bytes` is the process high-water mark (Darwin's
`ru_maxrss` is already bytes; platforms that report KiB are normalized by the
harness). The 15-second per-phase ceilings are intentionally generous safety
limits for CI and catch accidental unbounded work; they are not product-frame
budgets or cross-machine performance claims.

This gate measures CPU-side framework work and retained memory only. It does
not claim GPU upload latency, display-vsync pacing, battery/energy use, mobile
thermal behavior, or hosted transport cost. Those require a real Skia GPU
surface, device hosts, or WasmBrowser/remote transport fixtures and remain
separate validation work.
