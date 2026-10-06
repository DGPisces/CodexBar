---
summary: "Validation and performance limits for native Codex turn timing in Usage & Spend."
read_when:
  - Reviewing turn throughput or first-token timing in spend sessions
  - Reproducing the synthetic turn-performance benchmark
---

# Spend session turn performance validation

Local prototype measured on arm64 macOS 27 with Swift 6.4 in a debug build.
Baseline: `6a26b2e9b1b60471970deb6fe663f9e5f284e2ce`.
Parser revision: 9; parser hash: `e79fcc60eec6f0b0`.

## Metric contract

Native Codex sessions show total valid output tokens divided by total valid turn
duration, the median available first-token latency, and the number of timed turns.
Output includes reasoning tokens already contained in output. Turn duration
includes tools, retries, network and waiting; this is whole-turn throughput,
not streaming model throughput. Samples belong to their completion day.

Only successful completed turns with deduplicated authoritative request usage
matching the reported turn total are counted. Invalid owned usage or completion
timestamps invalidate timing; missing first-token timing only removes that
latency observation. Billing behavior is unchanged. Compatible previous cache
rows and pricing survive bounded timing backfill.

## UI evidence

These images render the production session component with **synthetic inputs**,
including normal and hidden-personal-info variants. They are component evidence,
not installed-app interaction evidence. English and Simplified Chinese, light and
dark appearances, and 820- and 420-point widths were checked locally.

![Synthetic English session rows](screenshots/spend-turn-performance-synthetic.png)

[Narrow synthetic session rows](screenshots/spend-turn-performance-synthetic-narrow.png)

## Synthetic benchmark

The smaller corpus contains 24 files / 960 turns / 3,840 requests. The larger
contains 96 files / 7,680 turns / 46,080 requests. Each corpus has three trials,
each with one cold read, three unchanged refreshes and one single-file append.
The following are medians. Cache reload includes SQLite decoding and session
projection, not app startup or UI interaction.

| Corpus | Path | Baseline | Prototype | Change |
| --- | --- | ---: | ---: | ---: |
| Smaller | Cold scan | 338.0 ms | 359.0 ms | +6.2% |
| Smaller | Unchanged refresh | 87.4 ms | 89.6 ms | +2.5% |
| Smaller | Append | 83.5 ms | 82.6 ms | -1.1% |
| Smaller | Unchanged cache reload / sessions | 73.1 ms | 77.3 ms | +5.9% |
| Larger | Cold scan | 3,677.6 ms | 3,910.2 ms | +6.3% |
| Larger | Unchanged refresh | 985.9 ms | 995.0 ms | +0.9% |
| Larger | Append | 898.6 ms | 889.0 ms | -1.1% |
| Larger | Unchanged cache reload / sessions | 847.8 ms | 892.0 ms | +5.2% |

Cold cache and side-file size increased by 6.5% / 4.5%. Unchanged refreshes
processed zero usage rows; append processed only the 4 / 6 new requests. Timed
turn counts matched the fixtures before and after append. The baseline harness
initially asserted zero file checks, confusing metadata checks with reparsing;
its timings were recorded but that baseline test invocation did not pass.
Prototype runs use the corrected zero-usage-rows assertion and passed.

Load matters: a separate run during other Swift compilation reached 11.37 seconds
for the larger cold scan and 2.84 seconds for its cache reload. These are debug
measurements on one machine, not a release performance guarantee or an app-memory
measurement. The existing larger cache path still warrants optimization.

## Validation and remaining gates

- `make check` passed: 2,816 Swift files, zero lint violations.
- 118 focused tests passed, including numeric and timestamp rejection, duplicates,
  partial scan / append, completion-only append, 128-byte resumable scans,
  revision-8 backfill, cache reopening and 25 unchanged refreshes.
- Localization catalog tests: 36 passed. Provider architecture tests: 48 passed.
- Production fresh and cached reads matched an independent reference for 41
  valid turns from privately copied native history; two invalid-usage candidates
  were rejected. Real usage values, source files and account data are withheld.
- All 143 groups / 1,569 selections were covered across batches. Runtime discovery
  matched the full 13,848-method inventory; this inventory count is not a count
  of passing test executions. 141 groups passed in those batches. Menu renderer
  timing and mocked cost-catch-up waits failed in two groups; final isolated
  reruns passed all 83 renderer and 30 catch-up tests. One other group hit its
  180-second deadline and passed the runner's isolated selection retries.
  **No single complete full-suite invocation passed.** The relevant renderer,
  catch-up scheduler and their tests were not modified; load causality remains
  unproven.

Full regression under controlled load, release-build measurements, installed-app
interaction and sustained operation remain release gates. Completely missing or
unrecognizable log records cannot be proven complete from the available protocol.
English, Simplified/Traditional Chinese and Italian strings are translated; other
catalogs currently use English fallback.

## Reproduce synthetic measurements

After building tests, from the repository root:

```sh
mkdir -p .build/turn-performance-proof
CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1 \
CODEXBAR_TEST_CODEX_FILE_ISOLATION=1 \
CODEXBAR_TEST_SESSION_FILE_ISOLATION=1 \
CODEXBAR_TOKEN_SPEED_BENCHMARK_OUTPUT="$PWD/.build/turn-performance-proof/benchmark.json" \
swift test --skip-build --filter CostUsageTurnPerformanceBenchmarkTests
```

Optional UI evidence uses `CODEXBAR_PERFORMANCE_UI_PROOF_DIR` and
`CODEXBAR_PERFORMANCE_UI_PROOF_WIDTH` with `SpendSessionPerformanceTests`.
The optional native-history test requires a private directory containing
`sessions/` and an independently prepared `expected.json`; it returns early
unless `CODEXBAR_PERFORMANCE_NATIVE_PROOF_DIR` is explicitly supplied.
