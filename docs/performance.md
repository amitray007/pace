# Performance verification

Pace measures performance separately from correctness tests. Timing assertions do not run inside
`make check`, because shared CI hardware can turn a timing fluctuation into a false failure.

## Quality-gate timing

`make format-check` runs the exact SwiftFormat version pinned in `Package.swift` once from the
repository root. This covers every tracked Swift file without repeating the same scan for each
Swift package target. Generated files under `.build` remain outside the source-quality gate.

On the development Mac used for the initial measurement, the previous command-plugin invocation
took 183.84 seconds and performed 18 overlapping scans. The single pinned executable pass took
13.69 seconds, a 92.6% wall-time reduction. Both commands reported a clean tree. The replacement
pass examined all 188 tracked Swift files, and a temporary malformed 189th file made the command
fail as expected. Treat these times as machine-specific observations. Verify coverage and failure
behavior again if the formatter command or package layout changes.

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

## Interaction benchmark

`make interaction-benchmark` measures the pointer-intent engine separately from AppKit event
delivery. One operation replays 120 pointer samples and timer ticks at 120 Hz, including deliberate
activation, provider travel, outside dismissal, scroll suppression, and mouse-button suppression.
The runner warms the release build, then records 25 samples with 200 complete replays per sample.

The local regression ceiling is 0.5 ms at p95 for one complete 120-sample replay. This reserves the
large majority of an 8.33 ms 120 Hz frame for event delivery, view updates, animation, and the
underlying application. The initial local baseline was 0.0044 ms at p95. Treat this value as a
machine-specific observation, not a cross-machine promise.

This benchmark proves deterministic engine cost only. It does not measure the global AppKit event
monitor, target-window updates, Core Animation commits, or physical pointer and scrollbar behavior.
Those remain running-application and Instruments checks.

## Running-application frame pacing

The deterministic motion sequence has also been captured with the Animation Hitches instrument on
the development Mac's built-in 120 Hz display. The capture used the unsigned universal Release app,
the mini initial state, and a three-second delay before reveal. It exercised reveal, provider
switches, rapid retargeting, and dismissal without provider access or pointer automation.

The initial implementation created and laid out the SwiftUI detail hierarchy on its first reveal.
That trace contained a 148.39 ms main-thread interaction delay and a 150 ms compositor hitch. Pace
now prepares one cached detail hierarchy for each visible provider while the rail remains hidden.
The animated container still owns position and opacity, and provider switches only reveal an
already prepared hierarchy unless its data or bounds changed.

In the final trace, no post-startup main-thread delay exceeded 33 ms. Between the first reveal at
three seconds and the end of the deterministic sequence, the largest compositor hitch was 16.67 ms;
the baseline contained five hitches over 33 ms. Prewarming moves a small amount of work into launch:
the final capture reported startup delays of 114.01 ms and 33.45 ms before the motion sequence was
eligible to begin. This is preferable to blocking the first user-triggered reveal, but it remains a
machine-specific observation rather than a launch-time guarantee.

Do not put the Instruments trace in `make check`. Each deferred trace is hundreds of megabytes and
requires Xcode to finalize it. Repeat the manual capture after changing the detail hierarchy,
hosting-view lifecycle, rail motion, or provider assets. Count post-startup delays with the
`potential-hangs` export and inspect the `hitches` export for the full rendered sequence.

This check covers one built-in 120 Hz display. A 60 Hz display, a second physical display, different
Mac hardware, and real pointer interaction still require separate running-application review.

## Visual benchmark

The visual benchmark extracts near-black pixels from a bounded region of the later Claude-detail
frame and from an app capture. That frame contains the final lower arc and settings control. It
normalizes both silhouettes into the capture's canvas without changing either aspect ratio. It
reports bounding boxes, aspect-ratio difference, foreground coverage, silhouette
intersection-over-union, and symmetric difference.

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
