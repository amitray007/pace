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
