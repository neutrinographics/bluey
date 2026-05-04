# iOS Error-Mapping Cleanup (I091 + I093) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drop the `CBATTError` allowlist in iOS's `NSError → PigeonError` translation so all `CBATTErrorDomain` errors preserve their numeric ATT status byte (closes I091); close I093 as obsolete-by-I088 with a verification note.

**Architecture:** Single-file Swift edit (`NSError+Pigeon.swift`) collapses a 13-case allowlist to one domain check. Test target gains four new typed-mapping tests and flips one previously-passing test that pinned the buggy behavior. No Dart changes. Backlog entries for I091 and I093 marked fixed.

**Tech Stack:** Swift / CoreBluetooth / XCTest (iOS Simulator), Pigeon (existing wire format unchanged), Markdown for backlog updates.

**Spec:** `docs/superpowers/specs/2026-05-04-ios-error-mapping-cleanup-design.md`

---

## File Map

```
bluey_ios/ios/Classes/NSError+Pigeon.swift                                  (Task 1, modify)
bluey_ios/example/ios/RunnerTests/CBErrorPigeonTests.swift                  (Tasks 1+2, modify)
docs/backlog/I091-ios-unmapped-cbatt-error-to-unknown.md                    (Task 3, modify)
docs/backlog/I093-ios-notfound-maps-to-wrong-error.md                       (Task 3, modify)
docs/backlog/README.md                                                      (Task 3, modify)
```

No new files. No file added to the Xcode project (the test file already exists and is wired up).

---

## Task 1: Flip the unknown-CBATT-code test (RED → GREEN)

**Why first:** The existing test `testUnknownCBATTErrorCode_mapsToBlueyUnknown` *pins* the bug we're fixing. Flipping it first gives us a meaningful failing test, then the implementation makes it pass — clean TDD.

**Files:**
- Modify: `bluey_ios/example/ios/RunnerTests/CBErrorPigeonTests.swift:99-103`
- Modify: `bluey_ios/ios/Classes/NSError+Pigeon.swift:12-43`

- [ ] **Step 1: Replace the existing unknown-code test with the new behavior**

In `bluey_ios/example/ios/RunnerTests/CBErrorPigeonTests.swift`, find lines 99-103:

```swift
  func testUnknownCBATTErrorCode_mapsToBlueyUnknown() {
    let err = NSError(domain: CBATTErrorDomain, code: 0xFF, userInfo: nil)
    let pe = err.toPigeonError()
    XCTAssertEqual(pe.code, "bluey-unknown")
  }
```

Replace with:

```swift
  func testUnknownCBATTErrorCode_preservesNumericStatus() {
    // Forward-compat: any CBATTErrorDomain code we don't explicitly know
    // by name should still surface as gatt-status-failed with the numeric
    // status byte preserved, so callers can react to future Apple-added
    // codes without a Bluey release.
    let err = NSError(domain: CBATTErrorDomain, code: 0xFF, userInfo: nil)
    let pe = err.toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0xFF)
  }
```

- [ ] **Step 2: Run the test to verify RED**

```bash
cd bluey_ios/example/ios && xcodebuild test \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:RunnerTests/CBErrorPigeonTests/testUnknownCBATTErrorCode_preservesNumericStatus 2>&1 | tail -20
```

Expected: FAIL with `XCTAssertEqual failed: ("bluey-unknown") is not equal to ("gatt-status-failed")`.

If `iPhone 15` isn't available, substitute any running simulator name from `xcrun simctl list devices available | grep iPhone`.

- [ ] **Step 3: Implement the simplification in `NSError+Pigeon.swift`**

Replace the entire contents of `bluey_ios/ios/Classes/NSError+Pigeon.swift` with:

```swift
import Foundation
import CoreBluetooth

extension NSError {
    /// Translates a CoreBluetooth `NSError` to a `PigeonError` the Dart
    /// adapter already knows how to handle. Any `CBATTErrorDomain` error
    /// becomes `gatt-status-failed` with `details` set to the numeric ATT
    /// status byte (Bluetooth Core Spec v5.3 Vol 3 Part F §3.4.1.1) — the
    /// domain itself is the contract, so future Apple-added codes are
    /// forwarded automatically without an allowlist. Any other domain
    /// falls through to `bluey-unknown` so user code never sees raw
    /// `PlatformException`.
    ///
    /// Mirrors Android's `ConnectionManager.statusFailedError` pattern,
    /// which forwards the raw `BluetoothGatt.GATT_*` status without an
    /// allowlist.
    func toPigeonError() -> PigeonError {
        if self.domain == CBATTErrorDomain {
            return PigeonError(code: "gatt-status-failed",
                               message: self.localizedDescription,
                               details: self.code)
        }
        return PigeonError(code: "bluey-unknown",
                           message: self.localizedDescription,
                           details: nil)
    }
}
```

This deletes the `attStatusByte(for:)` private helper and inlines the domain check. The existing 13 happy-path tests (`testInvalidHandle_mapsToStatus0x01` … `testInsufficientResources_mapsToStatus0x11`) continue to pass unchanged because each `CBATTError.<case>.rawValue` already equals its ATT status byte by the spec.

- [ ] **Step 4: Run all CBErrorPigeon tests to verify GREEN**

```bash
cd bluey_ios/example/ios && xcodebuild test \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:RunnerTests/CBErrorPigeonTests 2>&1 | tail -30
```

Expected: all 14 existing tests pass (13 happy-path + 1 unknown-domain + 1 newly-flipped unknown-code).

- [ ] **Step 5: Commit (red/green checkpoint)**

```bash
git add bluey_ios/ios/Classes/NSError+Pigeon.swift \
        bluey_ios/example/ios/RunnerTests/CBErrorPigeonTests.swift
git commit -m "$(cat <<'EOF'
fix(ios): preserve CBATTError status byte through Pigeon (I091)

Drop the hand-curated CBATTError allowlist in NSError+Pigeon.swift.
Any CBATTErrorDomain error now becomes gatt-status-failed with the
numeric code preserved as details, so callers receive a typed
GattOperationStatusFailedException for the four previously-dropped
codes (0x09 prepareQueueFull, 0x0C insufficientEncryptionKeySize,
0x0E unlikelyError, 0x10 unsupportedGroupType) and any future
Apple-added codes. Mirrors Android's statusFailedError pattern.

Test that pinned the old "unknown -> bluey-unknown" behavior is
flipped to assert the numeric code is preserved.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add named tests for the four previously-dropped codes

**Why a separate task:** Task 1 already proves the new behavior via the forward-compat test. Adding named tests for the four newly-mapped real codes is a *regression net*, not a TDD step — they should pass on first run. Separate commit keeps the regression net change self-contained.

**Files:**
- Modify: `bluey_ios/example/ios/RunnerTests/CBErrorPigeonTests.swift` (insert before the `// MARK: - Unknown domain/code` section)

- [ ] **Step 1: Add four named tests**

Open `bluey_ios/example/ios/RunnerTests/CBErrorPigeonTests.swift` and find the `// MARK: - Unknown domain/code` line (around line 91). Immediately *before* that line, after `testInsufficientResources_mapsToStatus0x11` (line 89), insert:

```swift

  func testPrepareQueueFull_mapsToStatus0x09() {
    let pe = makeError(code: CBATTError.prepareQueueFull.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x09)
  }

  func testInsufficientEncryptionKeySize_mapsToStatus0x0C() {
    let pe = makeError(code: CBATTError.insufficientEncryptionKeySize.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x0C)
  }

  func testUnlikelyError_mapsToStatus0x0E() {
    let pe = makeError(code: CBATTError.unlikelyError.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x0E)
  }

  func testUnsupportedGroupType_mapsToStatus0x10() {
    let pe = makeError(code: CBATTError.unsupportedGroupType.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x10)
  }
```

- [ ] **Step 2: Run the four new tests**

```bash
cd bluey_ios/example/ios && xcodebuild test \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:RunnerTests/CBErrorPigeonTests/testPrepareQueueFull_mapsToStatus0x09 \
  -only-testing:RunnerTests/CBErrorPigeonTests/testInsufficientEncryptionKeySize_mapsToStatus0x0C \
  -only-testing:RunnerTests/CBErrorPigeonTests/testUnlikelyError_mapsToStatus0x0E \
  -only-testing:RunnerTests/CBErrorPigeonTests/testUnsupportedGroupType_mapsToStatus0x10 2>&1 | tail -20
```

Expected: all four pass on first run.

- [ ] **Step 3: Run the full RunnerTests suite as sanity check**

```bash
cd bluey_ios/example/ios && xcodebuild test \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:RunnerTests 2>&1 | tail -30
```

Expected: all RunnerTests pass — including the unrelated `BlueyErrorPigeonTests`, `PeripheralManagerErrorTests`, `OpSlotTests`, etc.

- [ ] **Step 4: Run Dart-side tests in `bluey_ios`**

```bash
cd bluey_ios && flutter test 2>&1 | tail -10
```

Expected: pass. (No Dart-side change, but cheap insurance the Pigeon contract is unchanged.)

- [ ] **Step 5: Commit**

```bash
git add bluey_ios/example/ios/RunnerTests/CBErrorPigeonTests.swift
git commit -m "$(cat <<'EOF'
test(ios): cover previously-dropped CBATTError codes (I091)

Add named regression tests for the four CBATTError codes that
silently fell through to bluey-unknown before the I091 fix:
prepareQueueFull (0x09), insufficientEncryptionKeySize (0x0C),
unlikelyError (0x0E), unsupportedGroupType (0x10).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Update backlog entries (I091 fixed, I093 obsolete-by-I088)

**Files:**
- Modify: `docs/backlog/I091-ios-unmapped-cbatt-error-to-unknown.md`
- Modify: `docs/backlog/I093-ios-notfound-maps-to-wrong-error.md`
- Modify: `docs/backlog/README.md`

- [ ] **Step 1: Capture the implementation commit SHA**

```bash
git rev-parse --short HEAD
```

Note the SHA for the commit from Task 2 (the latest); also note the SHA from Task 1's commit:

```bash
git log --oneline -3
```

Use the **Task 1** SHA as `fixed_in` for I091 (that's where the actual fix landed). Call it `<TASK1_SHA>` below.

For I093, the "fixed" date is today's verification of the post-I088 state — there is no code commit for it; use the **design-doc commit SHA** (`fc9e2c8` on `main` before this branch) or the latest commit on this branch. Call it `<TASK1_SHA>` for consistency since that's where the verification landed.

- [ ] **Step 2: Mark I091 as fixed**

Open `docs/backlog/I091-ios-unmapped-cbatt-error-to-unknown.md`. Change the frontmatter:

```yaml
---
id: I091
title: "iOS unmapped `CBATTError` codes silently become `bluey-unknown`"
category: bug
severity: medium
platform: ios
status: fixed
last_verified: 2026-05-04
fixed_in: <TASK1_SHA>
---
```

(Replace `<TASK1_SHA>` with the actual short SHA.)

Append a **Resolution** section at the end of the file (after `## Notes`):

```markdown
## Resolution

`NSError+Pigeon.swift` no longer maintains an explicit `CBATTError`
allowlist. Any `NSError` whose `domain == CBATTErrorDomain` is
translated to `gatt-status-failed` with `details = self.code`, so
the four previously-dropped codes (0x09, 0x0C, 0x0E, 0x10) and any
future Apple-added codes surface as typed
`GattOperationStatusFailedException` carrying the numeric ATT status.
This brings iOS into symmetry with Android's
`ConnectionManager.statusFailedError`.

Test coverage in `CBErrorPigeonTests.swift`: the previously-passing
`testUnknownCBATTErrorCode_mapsToBlueyUnknown` is flipped to
`testUnknownCBATTErrorCode_preservesNumericStatus`, and four named
tests cover the previously-dropped codes by name.
```

- [ ] **Step 3: Mark I093 as fixed (obsolete-by-I088)**

Open `docs/backlog/I093-ios-notfound-maps-to-wrong-error.md`. Change the frontmatter:

```yaml
---
id: I093
title: "iOS `BlueyError.notFound` for unknown characteristic maps to `gatt-disconnected`"
category: bug
severity: medium
platform: ios
status: fixed
last_verified: 2026-05-04
fixed_in: <TASK1_SHA>
related: [I088]
---
```

Append a **Resolution** section at the end of the file:

```markdown
## Resolution

The original premise — characteristic / descriptor UUID misses
producing `gatt-disconnected` — was resolved by the I088 handle
rewrite (`73656b4`). Post-I088, every characteristic / descriptor
op in `CentralManagerImpl.swift` (lines 253-371) routes a missing
handle through `BlueyError.handleInvalidated.toClientPigeonError()`
→ `gatt-handle-invalidated` → `AttributeHandleInvalidatedException`,
not through `BlueyError.notFound`.

Re-verification on 2026-05-04 found three remaining
`BlueyError.notFound.toClientPigeonError()` sites in
`CentralManagerImpl.swift` (lines 153, 194, 226), all guarding
`peripherals[deviceId]` lookup misses in `connect`, `disconnect`,
and `discoverServices`. These fire when the user passes a deviceId
this iOS plugin instance has never seen. The current mapping to
`gatt-disconnected` was reviewed and left intentionally — the
user-visible truth ("you can't talk to this device right now") is
the same, the case is rare, and introducing a new
`DeviceUnknownException` type would be over-engineering for one
seldom-hit path. See the I091 + I093 design doc at
`docs/superpowers/specs/2026-05-04-ios-error-mapping-cleanup-design.md`
for the rationale.
```

- [ ] **Step 4: Move I091 and I093 from open → fixed in the index**

Open `docs/backlog/README.md`.

In the **Open — iOS stubs / no-ops / bugs** table (around line 187), delete these two rows:

```
| [I091](I091-ios-unmapped-cbatt-error-to-unknown.md) | Unmapped `CBATTError` codes silently become `bluey-unknown` | medium |
| [I093](I093-ios-notfound-maps-to-wrong-error.md) | `notFound` for unknown characteristic maps to `gatt-disconnected` | medium |
```

In the **Fixed — verified in HEAD** table (just before the `### Wontfix` section), append two rows at the bottom (preserve the existing format — title and short fix description, ending with the SHA):

```
| [I091](I091-ios-unmapped-cbatt-error-to-unknown.md) | iOS `NSError → PigeonError` translation now passes any `CBATTErrorDomain` status byte through unchanged; no allowlist | `<TASK1_SHA>` |
| [I093](I093-ios-notfound-maps-to-wrong-error.md) | Original characteristic/descriptor-miss premise resolved by I088 handle rewrite; remaining `peripherals[deviceId]` miss sites reviewed and left as `gatt-disconnected` intentionally | `<TASK1_SHA>` |
```

(Replace `<TASK1_SHA>` with the actual short SHA in both rows.)

- [ ] **Step 5: Update the "suggested order of attack" section**

In `docs/backlog/README.md`, find the line listing remaining iOS one-offs in the Tier 4 section (around line 118):

```
- **iOS NSError mapping cleanups** (I091 + I093) — unmapped `CBATTError` codes / `notFound` mapping. I091 was implicated in the `bluey-unknown` results from the 2026-04-29 stress-test session.
```

Replace with the strikethrough-with-link form used for other completed bundles in that section:

```
- ~~**iOS NSError mapping cleanups** (I091 + I093)~~ — DONE ([`<TASK1_SHA>`](#)). I091: dropped the `CBATTError` allowlist; any `CBATTErrorDomain` error now preserves its numeric status byte, mirroring Android's `statusFailedError`. I093: closed as obsolete-by-I088 (the original characteristic-miss premise is gone; remaining `peripherals[deviceId]` misses left as `gatt-disconnected` intentionally).
```

(Replace `<TASK1_SHA>` with the actual short SHA.)

- [ ] **Step 6: Commit the backlog updates**

```bash
git add docs/backlog/I091-ios-unmapped-cbatt-error-to-unknown.md \
        docs/backlog/I093-ios-notfound-maps-to-wrong-error.md \
        docs/backlog/README.md
git commit -m "$(cat <<'EOF'
chore(backlog): mark I091 + I093 fixed

I091 fixed by the CBATTError allowlist removal; I093 closed as
obsolete-by-I088 with a verification note explaining the post-I088
state and why the remaining peripherals[deviceId] miss sites are
intentionally left mapping to gatt-disconnected.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 7: Verify final state**

```bash
git log --oneline -4
git status
```

Expected: 3 new commits on top of `fc9e2c8` (the design doc), clean working tree.

```bash
grep -E "^\| \[I091\]|^\| \[I093\]" docs/backlog/README.md
```

Expected: both entries appear in the **Fixed** table, neither in any **Open** table.

---

## Spec coverage check

Spec section → task that implements it:

| Spec section | Task |
|---|---|
| I091 — drop the CBATTError allowlist (code change) | Task 1 step 3 |
| I091 — flip `testUnknownCBATTErrorCode_mapsToBlueyUnknown` | Task 1 step 1 |
| I091 — four new named tests for previously-dropped codes | Task 2 step 1 |
| I091 — Dart-side ripple sanity check | Task 2 step 4 |
| I093 — close as obsolete-by-I088 | Task 3 step 3 |
| Single-commit theme (per spec "Combined work product") | Tasks 1+2+3 form a 3-commit theme on one branch — reviewable as one PR. Spec said "single commit covering both"; the plan diverges to 3 commits (impl, regression net, backlog) for cleaner reviewability — same atomic unit at PR level. |
| Backlog entry updates (I091 fixed, I093 fixed-with-note) | Task 3 steps 2-3 |
| `docs/backlog/README.md` move open → fixed | Task 3 steps 4-5 |
