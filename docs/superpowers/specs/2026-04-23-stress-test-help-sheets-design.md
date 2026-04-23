# Stress Test Help Sheets

## Context

The stress tests page shows 7 test cards, each with a title and a one-line subtitle. Users unfamiliar with BLE testing need more context to understand what a test exercises and how to interpret the results panel. A help/info icon on each card provides this on demand without cluttering the default view.

## Design

### Trigger

A small circular ⓘ button sits at the far right of each card's header row, alongside the test icon, title, and subtitle. It is styled consistently with the card's existing design language:

- Size: 22×22 px, circular
- Background: `#F0F4F7` (`_kUuidBg`)
- Icon color: `#3F6187` (`_kAccent`)
- Label: the letter `i`, Inter SemiBold

### Interaction

Tapping ⓘ calls `showModalBottomSheet` with `isScrollControlled: true`. The sheet body wraps content in a `SingleChildScrollView` so it handles overflow gracefully on smaller devices, while remaining compact (no extra drag handle mechanics needed — content fits on screen for all 7 tests). The sheet uses:

- Corner radius: 20px top
- Handle bar: 32×3.5 px, `#E3E9ED`, centred, 14 px below top edge
- Background: white
- Padding: 16 px horizontal, 20 px bottom

### Sheet Structure

```
[handle]
[icon 36×36] [test name — Manrope Bold 15] / [subtitle — Inter 10 #596064]
────────────────────────────────────────────
WHAT IT DOES                             ← section label: Inter Bold 9 uppercase #3F6187 tracking 1px
<description paragraph(s)>              ← Inter 11 #596064 line-height 1.55
────────────────────────────────────────────
READING THE RESULTS
[stat pills]                             ← colour-coded dots matching results panel
<interpretation paragraph(s)>
```

Section labels use `_kAccent` (`#3F6187`) as a subtle blue-grey to distinguish them from body text. The divider is 1 px `#F0F4F7`.

Stat pills are compact rows of `dot + LABEL` matching the colours already used in `ResultsPanel`:
- ATTEMPTED — `#3F6187`
- SUCCEEDED — `#006D4A`
- FAILED — `#A83836`
- MEDIAN / P95 / ELAPSED — `#596064`

Only the stats that are meaningful for a given test are shown in the pills row.

### Content per test

#### Burst Write
**What it does:** Fires *count* writes to the echo characteristic back-to-back with no delay, waiting for each acknowledgement before moving on. Pushes the BLE write queue to capacity. *count* sets total writes; *bytes* is the payload per write — larger values stress fragmentation and reassembly. Enable *withResponse* to require an ATT acknowledgement per write; disable it for maximum throughput at the cost of delivery guarantees.

**Reading results:** A low failure rate confirms the stack handles sustained writes reliably. Any failures are broken down by exception type. A large gap between median and p95 latency points to occasional stalls — typically retransmission or flow-control backpressure.

Relevant stats: ATTEMPTED, SUCCEEDED, FAILED, MEDIAN, P95, ELAPSED

---

#### Mixed Ops
**What it does:** Runs *iterations* cycles of write → read → discover-services → request-MTU in sequence. Each cycle exercises a different GATT operation, catching bugs that only appear when operation types are interleaved — such as state machine races or incorrect handle caching after re-discovery.

**Reading results:** All operations in a cycle count as one attempt. A failure in any step of a cycle is recorded as a single failure with the exception type. Watch for `GattOperationFailedException` — it often indicates a state machine bug triggered by the specific sequence. Median and p95 latency measure end-to-end cycle time.

Relevant stats: ATTEMPTED, SUCCEEDED, FAILED, MEDIAN, P95, ELAPSED

---

#### Soak
**What it does:** Sends a write every *interval* milliseconds for *duration* seconds, mimicking a long-running sensor stream. Designed to expose memory leaks, handle exhaustion, and reliability degradation under sustained load rather than peak throughput.

*duration* is the total test wall time. *interval* controls the write cadence — lower values increase pressure. *bytes* is the payload per write.

**Reading results:** Focus on the failure rate over time, not throughput. A rising failure count late in the run (check elapsed vs attempted) suggests resource exhaustion. Connection loss during a soak is a strong signal of a platform-level memory or handle leak.

Relevant stats: ATTEMPTED, SUCCEEDED, FAILED, ELAPSED

---

#### Timeout Probe
**What it does:** Sends a special command telling the server to delay its acknowledgement by *delay past timeout* milliseconds beyond the per-operation timeout. Verifies that the client correctly raises `GattTimeoutException` and that subsequent operations succeed — confirming the stack recovers cleanly from a timeout.

**Reading results:** Expect exactly 1 failure (the timed-out write) and all subsequent writes to succeed. If more than one operation fails, the stack is not recovering from timeouts correctly. If none fail, the delay value is shorter than the actual per-op timeout in use.

Relevant stats: ATTEMPTED, SUCCEEDED, FAILED

---

#### Failure Injection
**What it does:** Issues a *drop-next* command to the server, then fires *writeCount* writes. The first write is intentionally dropped by the server, causing a timeout. The remaining writes should all succeed. Verifies that the client correctly classifies dropped writes as failures and resumes normal operation immediately after.

**Reading results:** A healthy result is exactly 1 failure (`GattTimeoutException`) followed by *writeCount − 1* successes. More failures indicate the stack is not resetting correctly after an injected error. Zero failures means the drop command was not received or the timeout is longer than the test waited.

Relevant stats: ATTEMPTED, SUCCEEDED, FAILED

---

#### MTU Probe
**What it does:** Requests *requestedMtu* bytes as the ATT MTU, then sends writes of *payloadBytes* each. Confirms that MTU negotiation completes and that payloads at or near the negotiated MTU size transfer without fragmentation errors.

*requestedMtu* is the value passed to the platform's MTU request API — the negotiated result may be lower depending on the peripheral. *payloadBytes* should be set to `requestedMtu − 3` (the 3-byte ATT header overhead) to test the maximum single-packet payload.

**Reading results:** Any failures indicate either a failed MTU negotiation or incorrect payload sizing. Check MEDIAN — unusually high latency at large MTU sizes can indicate retransmission due to RF congestion rather than stack bugs.

Relevant stats: ATTEMPTED, SUCCEEDED, FAILED, MEDIAN, P95, ELAPSED

---

#### Notification Throughput
**What it does:** Asks the server to fire *count* notifications, then counts how many are received and measures per-notification latency from burst start. Tests the client-side notification pipeline: subscription stability, delivery ordering, and throughput under a burst of inbound packets.

*count* is the total notifications requested. *payloadBytes* is the payload per notification — larger values test reassembly and buffer management on the receive path.

**Reading results:** SUCCEEDED should equal *count*. Any shortfall means notifications were dropped or arrived after the observation window closed. Median and p95 latency measure time from burst command to notification receipt — high p95 indicates OS-level scheduling jitter rather than BLE stack issues.

Relevant stats: ATTEMPTED, SUCCEEDED, FAILED, MEDIAN, P95, ELAPSED

---

### Architecture

All help content and the sheet widget live in the presentation layer. Two new files:

**`lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart`**
A private extension on `StressTest` exposing `_whatItDoes` and `_readingResults` string getters. The relevant stat enums for each test are also expressed as a list so the pills row renders only the stats that apply.

**`lib/features/stress_tests/presentation/widgets/stress_test_help_sheet.dart`**
A `StressTestHelpSheet` widget displayed via `showModalBottomSheet`. It takes a `StressTest` and builds the sheet from the content extension. The ⓘ button lives in `_CardHeader` in `test_card.dart` and calls a helper that shows the sheet.

This keeps the domain layer untouched and `test_card.dart` focused on layout — the help content is a self-contained concern.

## Testing

New widget tests in `test/stress_tests/presentation/widgets/stress_test_help_sheet_test.dart`:

- ⓘ button is present on every card (one test per `StressTest` value, or parametric)
- Tapping ⓘ opens the bottom sheet
- Sheet contains the test's display name
- Both section labels ("WHAT IT DOES", "READING THE RESULTS") are present
- Sheet is dismissible

Existing `test_card_test.dart` tests must continue to pass without modification.
