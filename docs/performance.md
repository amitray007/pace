# Performance verification

Pace measures performance separately from correctness tests. Timing assertions do not run inside
`make check`, because shared CI hardware can turn a timing fluctuation into a false failure.

## Core benchmark

`make benchmark` builds the benchmark executable with release optimization. It repeatedly creates
the deterministic visual-reference scenario, registers its four accounts, refreshes all provider
adapters, applies the normalized snapshots, and reads the final shared state.

The runner performs three warm-up operations and then records 25 samples with 20 complete pipeline
operations per sample. It reports the median, p95, minimum, and maximum time per operation as JSON.
The checksum keeps the compiler from removing the measured work.

The local regression ceiling is 5 ms at p95. This ceiling is intentionally much higher than the
expected result on a development Mac. It catches algorithmic or synchronization regressions while
leaving normal machine variance outside the gate.

Run a custom sample without a regression ceiling:

```sh
swift run -c release pace-benchmark core --samples 50 --iterations 50
```

This benchmark does not prove UI frame pacing, idle energy use, provider network latency, or disk
persistence speed. Add those measurements when their implementations exist. Rail animation still
requires Instruments and rendered 60 Hz and 120 Hz review.

## Visual benchmark

The visual benchmark extracts near-black pixels from the right side of the canonical primary-video
frame and from an app capture. It normalizes both silhouettes into the app's 324 x 416 point canvas
without changing either aspect ratio. It reports bounding boxes, aspect-ratio difference,
foreground coverage, silhouette intersection-over-union, and symmetric difference.

```sh
make visual-benchmark VISUAL_CAPTURE=.local/review/current/rail-claude.png
```

The command writes `metrics.json`, `reference-mask.png`, `capture-mask.png`, `overlay.png`, and
`difference.png` to `.local/review/visual-benchmark/`. Reference-only pixels are red. Capture-only
pixels are cyan. Matching foreground pixels are white in the overlay. The analyzer fills enclosed
text and icon holes before comparison so the score describes the outer black silhouette.

The measurement intentionally has no pass threshold. Text, pointer position, wallpaper, video
compression, and unpublished source geometry affect the score. Use it to locate drift and track
large regressions. The matched screenshot and human silhouette review remain the acceptance gate.
