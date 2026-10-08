---
summary: "Validation and performance limits for native Codex turn timing in Usage & Spend."
read_when:
  - Reviewing turn throughput or first-token timing in spend sessions
  - Reproducing the synthetic turn-performance benchmark
---

# Spend session turn performance validation

Validated on arm64 macOS 27 with Swift 6.4. Current installed-window code:
`7290172ec2fd8cc780269864b66e136560a24fac` (structured layout; final native
interaction remains blocked by a locked host session). The historical release comparison
used upstream baseline `ab32496d3c1f861981aa1a19aee2f933204f9bb9` and feature
production code `22fdcb88e8d77a03c9d8447f889012247d4bb483`.
The original validation used parser revision 9. The advanced details use parser revision 11 after merging main at `03a51bdcf`; the current generated parser hash is checked by `make check`.

## Metric contract

Native Codex session rows show total valid output tokens divided by total valid
turn duration, median available first-token latency, and median completed-turn
duration. The number of timed turns remains visible beside the collapsed disclosure and in its tooltip. Output includes reasoning tokens already contained in output. Duration
includes tools, retries, network and waiting; this is whole-turn throughput.
Session summaries can combine models and tool-heavy turns and are not a model
streaming benchmark. Samples belong to their completion day.

Only successful completed turns with deduplicated authoritative request usage
matching the reported turn total are counted. Invalid owned usage or completion
timestamps invalidate timing; missing first-token timing only removes that
latency observation. Billing behavior is unchanged. Compatible predecessor
ledger rows and saved pricing survive bounded timing backfill, including the
current upstream parser hash. Upstream's retained-report pricing migration still
clears the affected older report payload while keeping the ledger/checkpoints.

## Advanced details

Each native Codex session has a collapsed **Performance details** disclosure.
Details retain the selected completion-day range and include:

- P95 model-first-token and completed-turn duration using nearest-rank percentiles.
  Each metric needs at least 20 valid observations of its own; missing TTFT does
  not reduce the duration sample count. Twenty is a display threshold, not a
  statistical confidence guarantee.
- The middle 50% of per-turn output rates (nearest-rank P25–P75), after at least
  four completed turns. Different tasks and tool use can explain this spread.
- Cached-input tokens divided by total input tokens in eligible completed turns,
  with the cache sample coverage. Native Codex input already includes cached input;
  ratios are input-weighted, not averages of request percentages. Zero input and
  overflowing or invalid counters do not produce a ratio.
- Model and reasoning-effort groups, with timed-turn and available-TTFT counts,
  weighted whole-turn throughput and median latencies. Missing/mixed attribution
  remains unknown; these observations do not rank model capabilities.

Effort comes from the owning `turn_context.payload.effort`, joined by turn ID.
It is never inherited from another turn. Conflicting or cleared effort within
one turn is unavailable. A turn using multiple response models is unattributed.
Model-first-token may be reasoning and does not establish first visible answer
latency. Claude and OpenCodex rows remain without timing when their source does
not provide the validated native completion/usage contract.

Parser revision 11 uses existing bounded migration and retained-pricing logic.
Revision 8, 9 and 10 cache fixtures verify that authoritative ledger rows survive
backfill. No new background poll, account probe or external dependency is added.

## UI evidence and runtime boundary

These images render the production session component with **synthetic inputs**,
including normal and hidden-personal-info variants. English and Simplified
Chinese, light and dark appearances, and 820- and 420-point widths were checked.

![Synthetic English session rows](screenshots/spend-turn-performance-synthetic.png)

[Narrow synthetic session rows](screenshots/spend-turn-performance-synthetic-narrow.png)

A fresh release bundle was produced by `Scripts/package_app.sh release` with
ad-hoc signing and passed its resource and six-second launch smoke checks.
The follow-up application copy uses a separate bundle identity, isolated home,
configuration and app-group team, disabled Keychain/cookie access, and a failing
provider CLI stub. No credentials or account configuration were copied.

Those earlier artifacts did not establish installed-window behavior. The current
synthetic native-window checks and their bounded runtime limits are recorded in
[Structured session layout](#structured-session-layout-2026-10-08) and the historical
[installed-window verification](#installed-window-verification-2026-10-07) below.

## Follow-up date-filter review

A follow-up review reproduced a completion-day omission on the previously
validated feature: a turn starting at 23:59:55 and completing ten seconds later
had a valid timing sample, but its session row was discarded because all billed
requests belonged to the previous day. Session projection now retains valid
completion-day samples even when that day has no billing rows. Billing remains
on the original request day; no tokens or cost are moved into the completion day.

The dashboard also retains native Codex timing samples in the selected range
when the session file was modified outside that range. This exception does not
apply to other providers or OpenCodex sessions. Both cases have regression tests.
The follow-up parser hash is `d35c9fb00bee059b`; the historical receipts below
remain evidence for the earlier feature revision, not this follow-up.

Follow-up validation passed: 20 focused tests in three suites, and `make check`
with 2,819 Swift files and zero violations. The initial serial `make test` stopped
after 108 successful groups at a source-architecture check: moving the Codex-only
condition had left its required explanatory comment at the old location. The
comment was moved alongside the condition; no assertion was relaxed.

A complete fresh `./Scripts/test.sh --direct-workers 4` then passed all 143 groups
and all 1,571 discovered selections on their first attempt, with zero failures,
timeouts or retries (370.6 seconds total). This is the repository's supported
four-worker direct runtime, which verified 13,861 test methods against discovery;
it is distinct from the earlier serial invocation.

The existing English/Chinese, light/dark and narrow-width component renders were
visually reviewed again. Native application selection repeatedly timed out in
the desktop tool, while Finder remained accessible. Process startup and an idle
main-thread sample do not establish window interaction or responsiveness; that
was the evidence boundary for that earlier revision. Current native-window evidence
is recorded separately below.

## Release benchmark

Both production Core targets were independently built in release mode (`-O`).
`-enable-testing` allows the standalone adapter to access internal scanner
counters; it does not enable DEBUG code. The adapter is identical for both
builds, with `TURN_PERF_FEATURE` selecting only the optional sample assertion.
The scanner, cache and projection are production implementations.

The smaller corpus has 24 files / 960 turns / 3,840 requests; the larger has
96 files / 7,680 turns / 46,080 requests. Each has three trials, each with one
cold read, three unchanged refreshes and one single-file append. These are
medians. Reload includes SQLite decoding and session projection, not UI startup.

| Corpus | Path | Baseline | Feature | Change |
| --- | --- | ---: | ---: | ---: |
| Smaller | Cold scan | 194.0 ms | 197.0 ms | +1.5% |
| Smaller | Unchanged refresh | 59.5 ms | 57.1 ms | -4.0% |
| Smaller | Single-file append | 31.9 ms | 29.7 ms | -6.7% |
| Smaller | Cache reload / session projection | 47.8 ms | 48.6 ms | +1.5% |
| Larger | Cold scan | 2,009.1 ms | 2,099.9 ms | +4.5% |
| Larger | Unchanged refresh | 633.9 ms | 633.6 ms | -0.1% |
| Larger | Single-file append | 291.1 ms | 278.4 ms | -4.4% |
| Larger | Cache reload / session projection | 542.8 ms | 556.7 ms | +2.6% |

A second complete comparison after the full suite ended reversed the binary
order (feature, then baseline). It produced the following medians:

| Corpus | Path | Baseline | Feature | Change |
| --- | --- | ---: | ---: | ---: |
| Smaller | Cold scan | 201.1 ms | 190.4 ms | -5.3% |
| Smaller | Unchanged refresh | 55.8 ms | 55.9 ms | +0.2% |
| Smaller | Single-file append | 29.3 ms | 28.5 ms | -2.6% |
| Larger | Cold scan | 1,958.2 ms | 2,200.7 ms | +12.4% |
| Larger | Unchanged refresh | 610.9 ms | 621.1 ms | +1.7% |
| Larger | Single-file append | 277.7 ms | 274.8 ms | -1.1% |

The larger cold overhead was 4.5% in the first comparison and 12.4% in the
repeat, so the first figure alone is insufficient. Warm refresh overhead was
between -0.1% and +1.7%; cache/session projection retained a few-percent overhead.
The lower smaller-corpus timings are measurement variation, not a claimed
speedup. Both complete result sets are retained in the raw proof.

Cold cache and side files grew by 6.5% / 4.5% (4.32 to 4.60 MiB / 49.54 to
51.80 MiB). All unchanged refreshes processed zero usage rows; append processed
only the 4 / 6 new requests. Every feature run matched expected timing counts,
including the one appended turn.

The complete benchmark process peaked at 1.21 / 1.23 GiB RSS, a 1.7% increase.
This includes fixture construction, all trials, scanning and cache projection;
**it is not an application memory or leak measurement**. Repository tests and
other host work were active, so small changes are noisy observations. The
larger cached projection still takes roughly half a second; these finite
measurements are not a release performance guarantee.

[Raw synthetic results and build metadata](proofs/spend-turn-performance-release.json)
and [standalone adapter](proofs/spend-turn-performance-release-probe.swift.txt)
are public and contain no real usage data.

## Native-history validation

Production fresh and reopened-cache reads matched an independent reference for
41 valid turns in six privately copied native files (75,187,821 bytes). Full
usage-counter validation excluded two output-only candidates, including owned
records with reasoning greater than output. The source histories were left
untouched. No credentials, identities, actual token counts, monetary values or
real throughput/latency values are published.

[Redacted receipt](proofs/spend-turn-performance-native.json) and the
[independent offline join](proofs/spend-turn-performance-native-reference.py)
are available. The reference is intentionally limited to this dependency-closed
root-session corpus; adversarial/fork/partial-scan behavior is covered by Swift
tests. Private reference output must stay private.

## Regression validation

- `make check` passed: 2,818 Swift files, zero lint violations.
- 123 focused tests in seven suites passed after the upstream rebase, including
  numeric/timestamp rejection, duplicate ownership, partial/completion-only
  append, bounded revision-8 backfill, pricing migration and cache reopening.
- The opt-in native-history proof passed separately with its input supplied;
  ordinary full-suite execution intentionally skips its private-input branch.
- `make test` passed in one complete invocation: all 143 groups / 1,570
  discovered selections passed on their first attempt, with zero failures,
  timeouts or retries (1,221 seconds total). This uses the repository default
  serial runner and unmodified assertions; earlier interrupted preparation
  runs are not counted as complete passes.

English, Simplified/Traditional Chinese and Italian captions are translated;
other catalogs currently use English fallback. Completely missing or
unrecognizable log records cannot establish sample completeness from the
available protocol. Current installed-window checks are recorded separately below; they do not
establish long-term operation or release-mode responsiveness.

## Reproduction

Use two clean worktrees at the baseline and feature commits. Copy the linked
adapter to `ProofTarget/main.swift` in each, and temporarily append these
SwiftPM manifest entries:

```swift
package.products.append(.executable(name: "TokenSpeedReleaseProbe", targets: ["TokenSpeedReleaseProbe"]))
package.targets.append(.executableTarget(name: "TokenSpeedReleaseProbe", dependencies: ["CodexBarCore"], path: "ProofTarget"))
```

Build each independently using `swift build -c release --product
TokenSpeedReleaseProbe -j 2 -Xswiftc -enable-testing`; add `-Xswiftc
-DTURN_PERF_FEATURE` for the feature adapter. Set
`CODEXBAR_TOKEN_SPEED_BENCHMARK_OUTPUT` when running the archived standalone
adapter binary (it predates the newer test-benchmark environment name).
No test-only flag changes the scanner execution path. Restore the temporary
manifest afterward, and never copy build products between worktrees.

The existing opt-in Swift test benchmark uses the same fixture through
`CostUsageTurnPerformanceBenchmarkTests`, with
`CODEXBAR_PERFORMANCE_BENCHMARK_OUTPUT`. Optional component rendering uses
`CODEXBAR_PERFORMANCE_UI_PROOF_DIR` and `CODEXBAR_PERFORMANCE_UI_PROOF_WIDTH`
with `SpendSessionPerformanceTests`. The native-history proof requires a private
directory with `sessions/` and independently prepared `expected.json`, supplied
through `CODEXBAR_PERFORMANCE_NATIVE_PROOF_DIR`.

## Advanced-details validation before upstream merge (2026-10-07)

The advanced-details receipt is separate from earlier release comparisons:
[redacted receipt](proofs/spend-turn-performance-details.json). Twenty-eight
focused tests in four suites passed, including plain and escaped JSON keys/values,
Foundation fallback, conflicting/missing effort, native-only completion-date
filtering, percentile thresholds, input-weighted cache ratios and revision 8/9 backfill preserving authoritative ledger rows. The production fetcher and reopened
cache matched the independent extended reference for 41 turns in six copied native
files; no real usage values or identities are published.

Current static checks passed (`make check`, 2,821 Swift files, zero violations).
The complete supported `./Scripts/test.sh --direct-workers 4` invocation exited
successfully: all 143 groups / 1,572 selections passed, with 141 groups passing
first attempt and two recovering on the runner's fresh-process retry (618.4 s;
zero group timeouts). The initial issues were an unrelated WebKit fixture wait
in `OpenAISubscriptionMetadataTests` and a generic weekly-history persistence
expectation in `UsageStorePlanUtilizationTests`. No assertions were changed or
failures suppressed. This is a retry-assisted pass, not a clean first-pass run.
Advanced-detail strings are translated in English, Simplified Chinese and Italian;
the other synchronized catalogs currently use English fallback for those strings.

After merging main at `03a51bdcf`, 167 focused tests in 12 suites passed, with
private native input supplied; the fresh/reopened reference still matched all 41
turns. `make check` passed with 2,848 Swift files and zero violations. Parser
revision 11 retains the newer mirror deduplication and shared report projections;
revision 8/9/10 backfill and both upstream/current-PR hash migrations are covered.
The complete repository-supported merged regression passed all 144 groups /
1,591 selections first attempt (339.0 seconds), with zero failures, retries or
timeouts; the direct runtime verified 14,050 methods against discovery.

The merged synthetic debug benchmark ran three trials each for 24 sessions / 960
turns and 96 sessions / 7,680 turns. Advanced summary construction medians were
1.7 ms and 13.9 ms respectively; the larger maximum was 17.1 ms. Every unchanged
refresh reprocessed zero usage rows. These are absolute timings on a shared host,
not a release comparison, app responsiveness measurement or memory-leak proof.

![Synthetic production performance details](screenshots/spend-turn-performance-details-synthetic.png)

The screenshot above is a production-component render with synthetic values.
The installed-window evidence for the final code revision is separate below.


## Installed-window verification (2026-10-07)

The installed application was rebuilt in debug mode with ad-hoc signing from
`d66ac3e9cc37eb4a1e8f46b143aec35f8887ec31`, with a clean tracked working tree.
Executable SHA-256:
`310d986bf7d433cf42eae40f32ef8b5d84e02fba7e12f5812d7627e48f58742f`.
Its separate bundle identity, home, defaults, config and app-group team contain
only a synthetic Codex session. Both `CODEX_HOME` and `CODEX_SQLITE_HOME` point
into that profile; Keychain access, cookies, automatic updates and real CLI
probes are disabled. The runtime cache contained exactly that one source and
24 usage rows. No real account configuration or credentials were copied.

The real Usage & Spend window was operated through System Events after explicit
user authorization. It exposed a day-scoping bug: selecting a chart day updated
model details but retained the full range's performance samples. The final code
also intersects native timing samples with the selected completion day. Session
billing totals retain the existing range accounting; no usage is moved between
billing dates. A regression covers today, yesterday, cleared selection and an
empty selected day, including sample thresholds and model/cache detail summaries.

| Selection | Turns | Median model first token | Whole-turn output | Median duration |
| --- | ---: | ---: | ---: | ---: |
| Seven days / cleared | 24 | 0.8 s | 16.8 tok/s | 15.8 s |
| Today | 12 | 1.0 s | 17.3 tok/s | 18.8 s |
| Yesterday | 12 | 0.7 s | 16.1 tok/s | 12.8 s |

Each selection matched the independent synthetic reference. Seven days displayed
P95 duration 21.0 s, P95 first token 1.2 s, speed quartiles 16.0–17.3 tok/s and
77.5% cached input. Each single day displayed the insufficient-sample P95 labels
and six turns per model/effort group. Clearing restored 24 turns. Details remained
readable within the actual 800-by-568-point window and scrollable viewport.

![Installed expanded window, synthetic data](screenshots/spend-turn-performance-native-window-expanded-synthetic.png)

[Collapsed window](screenshots/spend-turn-performance-native-window-collapsed-synthetic.png) ·
[Today](screenshots/spend-turn-performance-native-window-today-synthetic.png) ·
[Yesterday](screenshots/spend-turn-performance-native-window-yesterday-synthetic.png)

These are captures of the installed window, with synthetic values clearly labeled
inside the window, rather than component renders. No host desktop or real usage
is included.

A further 96.0-second interaction smoke completed 20 expand/collapse pairs,
three real date-picker/filter/clear cycles and 12 scroll operations; all state
assertions passed without process exit or automation timeout. The app returned
to idle afterward. This is bounded debug-build evidence on a shared host during
full-suite execution, not a release latency benchmark or long-term leak proof.
The main-thread watchdog recorded initial launch/window delays of 485, 275,
1,641 and 472 ms and two later 189 ms delays. These observations do not attribute
a regression to this feature and are not a claim of zero stalls.

After that full suite ended, three close/reopen cycles retained the correct
session state. The watchdog recorded two additional warm-window delays of 274
and 384 ms; these should not be described as a stall-free UI. Their cause and
release-mode significance are not established by this debug smoke.

The final selected-day fix passed 52 focused tests in two suites and `make check`
with 2,848 Swift files and zero violations. A fresh complete supported four-worker
regression exited 0: 144 groups / 1,591 selections, with 14,051 runtime methods
verified against discovery (1,013.3 seconds). This was a retry-assisted pass:
142 groups passed first attempt, the WebKit metadata fixture group recovered on
one fresh group retry, and a cost-store group reached the 180-second aggregate
limit before its 12 selections passed separately. Assertions were not changed
or failures suppressed. Earlier full-suite receipts above belong to their stated
revisions. See the [exact receipt](proofs/spend-turn-performance-details.json).

A separate post-suite confirmation of `OpenAISubscriptionMetadataTests` passed
all seven XCTest cases without retry. This does not erase the full-run first-pass
fixture timeout recorded above.

## Structured session layout (2026-10-08)

Session rows now separate the title/billing header from the performance metrics.
The provider icon stays beside the title, with billing as secondary text. The
visible session rank was removed. Three primary values show first-token latency,
whole-turn output and completed-turn duration; labels remain smaller than values.

The initially collapsed disclosure keeps the timed-turn count visible. Expanded
details use four aligned fields for P95 first token, P95 duration, the middle 50%
of per-turn speeds and cached input, including its coverage. Missing values use
an em dash with an independent insufficient-sample note. Model/effort observations
use a comparison table with aligned numeric columns and partial TTFT coverage;
narrow widths switch to compact model blocks. Explanation is available through
help and accessibility text instead of repeated prose in each row.

The data contract above remains unchanged. These observations include workload,
reasoning, tools and waits and are not a model streaming-speed leaderboard.

Validation and screenshots are recorded separately from the October 7 layout.

Production UI renders were checked in English and Simplified Chinese, light and
dark, at 320, 420 and 820 points. The installed `70937cc62` window completed the
seven-day/collapse/expand/today/clear/yesterday/clear checks, with 24/12/12 timed
turns matching the independent synthetic reference. Continuous expansion was
interrupted when its AX window became unavailable; the process remained alive.
These screenshots belong to that UI revision, which is unchanged by the latest
upstream merge.

![Structured details in the installed window, synthetic data](screenshots/spend-turn-performance-layout-expanded-synthetic.png)

[Collapsed](screenshots/spend-turn-performance-layout-collapsed-synthetic.png) ·
[Selected day with insufficient P95 samples](screenshots/spend-turn-performance-layout-today-synthetic.png) ·
[Narrow dark component](screenshots/spend-turn-performance-layout-narrow-dark-synthetic.png)

The latest source merges upstream `844b0e19b`. Parser revision 11 now has hash
`c0f8e9be04d824c2`; value-preserving string-sharing and earlier timing caches
remain compatible, including saved report pricing. Forty-six focused tests in
five suites passed, including all 47 predecessor-adoption parameter cases.
`make check` passed with 2,856 Swift files and zero violations. A fresh complete
four-worker regression exited 0: all 144 groups and 1,599 selections passed on
the first attempt, with no failures, timeouts or retries (592.1 seconds; runtime
inventory verified 14,098 methods).

The first layout run stopped at the Italian unchanged-key allowlist. Four shared
unit/numeric formats were registered explicitly; exact set equality remains.
The failed run is retained in the receipt and is not counted as passed.

A fresh debug/ad-hoc bundle was built from the clean merged source. Its isolated
cache contains exactly one synthetic file and 24 usage rows; no credentials were
copied. Final native-window repetition is **not passed**: macOS reported
`CGSSessionScreenIsLocked = 1`; the accessibility windows were returned with the
wrong roles, and target-window capture was unavailable. The process stayed
running. Before diagnosing the lock, the watchdog recorded 540/840/384 ms on a
shared host with the regression concurrently active. This is not stall-free or
release performance evidence. A restart while locked recorded 393/557 ms; it
also does not establish interactive responsiveness. Unlocking the host is required to finish this
runtime gate. Earlier October 7 runtime receipts remain historical evidence.
