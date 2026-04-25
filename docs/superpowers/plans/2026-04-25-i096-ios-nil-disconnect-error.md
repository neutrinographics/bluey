# I096 iOS Nil-Error Disconnect — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When iOS `CentralManagerImpl.didDisconnectPeripheral` receives `error: nil`, drain pending ops as `gatt-disconnected` instead of `bluey-unknown`. Closes I087 (failure-injection auto-reconnect) as a side effect.

**Architecture:** Single-block change in `CentralManagerImpl.swift`. Replaces the `?? BlueyError.unknown.toClientPigeonError()` fall-through with an explicit `PigeonError(code: "gatt-disconnected", ...)` when iOS provides no NSError. No Dart-side changes, no tests at the unit level (see spec's TDD section — this is a Swift-only translation fix with verification on-device).

**Tech Stack:** Swift, CoreBluetooth, Pigeon-generated bindings.

**Spec:** [`docs/superpowers/specs/2026-04-25-i096-ios-nil-disconnect-error-design.md`](../specs/2026-04-25-i096-ios-nil-disconnect-error-design.md).

**Working directory for all commands:** `/Users/joel/git/neutrinographics/bluey/.worktrees/i096-nil-disconnect-error` (created in Task 1).

**Branch:** `fix/i096-nil-disconnect-error`, off `main` (does **not** carry the `investigate/i091-cbatt-error-instrumentation` diagnostic commits — those are reverted by virtue of branching fresh).

---

## File Structure

| File | Role |
|---|---|
| `bluey_ios/ios/Classes/CentralManagerImpl.swift` | The fix — one block at `didDisconnectPeripheral` |
| `docs/backlog/I096-ios-nil-disconnect-error-to-unknown.md` | New backlog entry, status `fixed` after merge |
| `docs/backlog/I087-failure-injection-no-auto-reconnect.md` | Mark `fixed`, redirect to I096 |
| `docs/backlog/I091-ios-unmapped-cbatt-error-to-unknown.md` | Add cross-reference note (stays open) |
| `docs/backlog/README.md` | Move I087 to Fixed table, add I096 row, drop the I087+I091 attack-plan line |

---

## Task 1: Set up the feature worktree

**Rationale:** Branch off `main` (not the diagnostic branch) so the fix doesn't inherit the `[I091-DIAG]` `NSLog` calls. Those reverts come implicitly from branching fresh.

- [ ] **Step 1: Confirm primary worktree state**

```bash
cd /Users/joel/git/neutrinographics/bluey
git status
git log --oneline -3
```

Expected: on `main`, working tree clean, recent commit `d59506e docs(spec): I096 iOS nil-error disconnect → bluey-unknown design`.

- [ ] **Step 2: Create the feature worktree**

```bash
git worktree add .worktrees/i096-nil-disconnect-error -b fix/i096-nil-disconnect-error
```

Expected: worktree created at `.worktrees/i096-nil-disconnect-error`, on new branch `fix/i096-nil-disconnect-error`.

- [ ] **Step 3: Verify clean baseline (no diagnostic commits, no extra files)**

```bash
cd .worktrees/i096-nil-disconnect-error
grep -n "I091-DIAG" bluey_ios/ios/Classes/*.swift 2>&1
```

Expected: **no matches**. The diagnostic instrumentation isn't on this branch.

```bash
git log --oneline -1
```

Expected: matches main's HEAD (`d59506e`).

- [ ] **Step 4: Pub get to ensure baseline builds**

```bash
cd bluey && flutter pub get 2>&1 | tail -3
cd ..
```

Expected: deps fetched without errors.

---

## Task 2: Apply the Swift fix

**Rationale:** Single-block change in `CentralManagerImpl.swift`. The diff is exactly what the spec describes.

**Files:**
- Modify: `bluey_ios/ios/Classes/CentralManagerImpl.swift` (one block, around line 493-496 in main)

- [ ] **Step 1: Locate the exact block**

The current code in `didDisconnectPeripheral`:

```swift
        // Drain all remaining pending completions with the disconnect error.
        let pigeonError: Error = (error as NSError?)?.toPigeonError()
            ?? BlueyError.unknown.toClientPigeonError()
        clearPendingCompletions(for: deviceId, error: pigeonError)
```

Use `grep -n "Drain all remaining" bluey_ios/ios/Classes/CentralManagerImpl.swift` if line numbers have drifted.

- [ ] **Step 2: Replace the block**

Replace exactly the three-line `let pigeonError: Error = ...` (including the `??` continuation) with:

```swift
        // Drain all remaining pending completions with the disconnect error.
        // iOS reports nil error for graceful disconnects: peer-initiated
        // clean shutdown, or our own cancelPeripheralConnection (e.g.
        // LifecycleClient declared the peer unreachable). The link is gone
        // either way; map to gatt-disconnected so callers (LifecycleClient,
        // example-app reconnect cubit) recognise the dead-peer signal.
        // Falling through to BlueyError.unknown was wrong — see I096.
        let pigeonError: Error
        if let nsError = error as? NSError {
            pigeonError = nsError.toPigeonError()
        } else {
            pigeonError = PigeonError(code: "gatt-disconnected",
                                      message: "Peripheral disconnected",
                                      details: nil)
        }
        clearPendingCompletions(for: deviceId, error: pigeonError)
```

The earlier `// Drain all remaining pending completions with the disconnect error.` comment line is part of what you replace — the new block has its own richer comment.

- [ ] **Step 3: Verify only one site changed and it's the right one**

```bash
git diff bluey_ios/ios/Classes/CentralManagerImpl.swift
```

Expected: a single hunk in `didDisconnectPeripheral`. **Do not** change `didFailToConnect` — its nil-error branch is intentionally left alone (see spec's non-goals).

- [ ] **Step 4: Run the Dart-side test suite (sanity)**

The Swift change has no Dart-side dependencies, but run the suite to confirm nothing in the test fakes assumes the old shape:

```bash
cd bluey && flutter test 2>&1 | tail -3
cd ..
```

Expected: all tests pass. (Test count should match `main`'s baseline — no new tests, no removed tests.)

- [ ] **Step 5: Commit the fix**

```bash
git add bluey_ios/ios/Classes/CentralManagerImpl.swift
git commit -m "$(cat <<'EOF'
fix(ios): nil-error disconnect maps to gatt-disconnected (I096)

iOS calls didDisconnectPeripheral(error: nil) for graceful disconnects
(peer-initiated clean shutdown, or our own cancelPeripheralConnection).
Pre-fix, the nil-error branch fell through to BlueyError.unknown →
bluey-unknown, which Dart callers (LifecycleClient, example-app reconnect
cubit) don't recognise as a dead-peer signal. Map to gatt-disconnected
instead — semantically correct and symmetric with every other dead-peer
path in the codebase.

Closes I087 (failure-injection no auto-reconnect) as a side effect: the
example app's reconnect cubit keys off GattOperationDisconnectedException
and now sees the right shape.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: File the I096 backlog entry

**Files:**
- Create: `docs/backlog/I096-ios-nil-disconnect-error-to-unknown.md`

- [ ] **Step 1: Get the SHA of the fix commit**

```bash
git log --oneline -1 --format=%H
```

Record the SHA (let's call it `<FIX_SHA>` in the snippets below — replace with the actual short SHA).

- [ ] **Step 2: Create the entry**

Write `docs/backlog/I096-ios-nil-disconnect-error-to-unknown.md` with:

```markdown
---
id: I096
title: "iOS `didDisconnectPeripheral` with `error: nil` produces `bluey-unknown` instead of `gatt-disconnected`"
category: bug
severity: high
platform: ios
status: fixed
last_verified: 2026-04-25
fixed_in: <FIX_SHA>
related: [I087, I091, I079]
---

## Symptom

In the failure-injection stress test (post-I079), connection teardown
surfaces as `BlueyPlatformException(bluey-unknown) × 1` followed by
`GattOperationDisconnectedException × 7`. The example app's reconnect
cubit doesn't recognise the leading `bluey-unknown` as a dead-peer
signal and stops attempting to recover. Result: connection is lost
permanently after a single dropped server response.

## Location

`bluey_ios/ios/Classes/CentralManagerImpl.swift` — `didDisconnectPeripheral`.
Pre-fix, the nil-error branch in:

```swift
let pigeonError: Error = (error as NSError?)?.toPigeonError()
    ?? BlueyError.unknown.toClientPigeonError()
```

falls through to `BlueyError.unknown.toClientPigeonError()` →
`PigeonError(code: "bluey-unknown", ...)`.

## Root cause

Apple's CoreBluetooth calls `peripheral(_:didDisconnectPeripheral:error:)`
with `error: nil` for *graceful* disconnects: either we ourselves called
`cancelPeripheralConnection` (e.g. `LifecycleClient` declared the peer
unreachable and tore down), or the peer initiated a clean shutdown.

`error: nil` does **not** mean "an unknown error occurred" — it means
"no metadata, link is gone." Mapping that to `BlueyError.unknown` is
semantically wrong; the link being gone is itself the meaningful signal,
and `gatt-disconnected` is the established Dart-side shape for that.

Pre-I079, this code path was rarely hit because the *server* tore down
the link in the failure-injection scenario, providing iOS with a
`CBError` (handled correctly by `nsError.toPigeonError()`). I079's
fix shifted the disconnect cause from server-initiated to
self-initiated, exposing this bug.

## Notes

Fixed in `<FIX_SHA>` by mapping the nil-error branch to
`PigeonError(code: "gatt-disconnected", ...)` directly:

```swift
if let nsError = error as? NSError {
    pigeonError = nsError.toPigeonError()
} else {
    pigeonError = PigeonError(code: "gatt-disconnected",
                              message: "Peripheral disconnected",
                              details: nil)
}
```

This also closes [I087](I087-failure-injection-no-auto-reconnect.md) as
a side effect — the example app's reconnect cubit now recognises the
disconnect signal.

The parallel nil-error fall-through in `didFailToConnect` is **not**
changed by this fix. No diagnostic evidence it fires in practice, and
connect-failure semantics differ from disconnect (no established
`gatt-connection-failed` code). Filed as future work if it ever
surfaces.

## Future work

Build a Swift test target for `bluey_ios` so translation logic
(`BlueyError`, `NSError+Pigeon`, `OpSlot`, `CentralManagerImpl`
delegate methods) can have unit tests. This bug would have been a
natural early test target. Not blocking; out of scope for this fix.
```

Replace `<FIX_SHA>` literally with the SHA from Step 1 (short form, e.g. `8a1b2c3`).

- [ ] **Step 3: Commit**

```bash
git add docs/backlog/I096-ios-nil-disconnect-error-to-unknown.md
git commit -m "chore(backlog): file I096 — iOS nil-error disconnect → bluey-unknown"
```

---

## Task 4: Close I087 with redirect

**Files:**
- Modify: `docs/backlog/I087-failure-injection-no-auto-reconnect.md`

- [ ] **Step 1: Update frontmatter**

Replace the existing frontmatter block at the top of `docs/backlog/I087-failure-injection-no-auto-reconnect.md` with:

```yaml
---
id: I087
title: Connection doesn't auto-reconnect after failure-injection-style disconnect with unmapped platform error
category: bug
severity: medium
platform: ios
status: fixed
last_verified: 2026-04-25
fixed_in: <FIX_SHA>
related: [I079, I091, I090, I096]
---
```

Use the same `<FIX_SHA>` recorded in Task 3 Step 1.

- [ ] **Step 2: Replace the existing `## Notes` section**

Find the `## Notes` heading. Replace **only** the Notes section content (preserve `## Symptom`, `## Location`, `## Root cause`) with:

```markdown
## Notes

Fixed in `<FIX_SHA>` by [I096](I096-ios-nil-disconnect-error-to-unknown.md).

The hypothesis in this entry's original Notes ("fixing I091 may fix this
as a side effect") was directionally right — the bluey-unknown was
indeed the cascade trigger — but pointed at the wrong code path.
Diagnostic instrumentation revealed the bluey-unknown comes from
`CentralManagerImpl.didDisconnectPeripheral` falling through on
`error: nil`, **not** from `NSError.toPigeonError()`'s `CBATTError`
allowlist gap.

I091 remains open for the original CBATTError allowlist concern (no
production evidence it fires; low priority).
```

Use the same `<FIX_SHA>`.

- [ ] **Step 3: Commit**

```bash
git add docs/backlog/I087-failure-injection-no-auto-reconnect.md
git commit -m "chore(backlog): close I087 — fixed by I096 (nil-error disconnect)"
```

---

## Task 5: Cross-reference I091

**Rationale:** I091 stays open (different bug, no production evidence) but should point readers at I096 to avoid future confusion.

**Files:**
- Modify: `docs/backlog/I091-ios-unmapped-cbatt-error-to-unknown.md`

- [ ] **Step 1: Add a redirect note above the Symptom section**

Read the existing I091 content. Find the `## Symptom` heading. Insert immediately **above** it (between frontmatter and Symptom):

```markdown
> **Note (2026-04-25):** I091 was originally suspected as the cause of
> [I087](I087-failure-injection-no-auto-reconnect.md)'s failure-injection
> reconnect bug. Diagnostic instrumentation showed the actual cause was
> in `CentralManagerImpl.didDisconnectPeripheral`, not `NSError+Pigeon`.
> See [I096](I096-ios-nil-disconnect-error-to-unknown.md). I091 remains
> open for the original `CBATTError` allowlist gap, which has no
> production evidence of firing — low priority.

```

(Keep the trailing blank line so `## Symptom` is properly separated.)

- [ ] **Step 2: Commit**

```bash
git add docs/backlog/I091-ios-unmapped-cbatt-error-to-unknown.md
git commit -m "chore(backlog): cross-reference I091 → I096 (different code path)"
```

---

## Task 6: Update backlog README

**Files:**
- Modify: `docs/backlog/README.md`

- [ ] **Step 1: Drop the I087+I091 line item from "Suggested order of attack"**

Find the numbered list under `## Suggested order of attack`. There's a line item starting with `**I087 + I091 (follow-up after #1)**`. **Delete the entire numbered entry** (the multi-line bullet) and renumber subsequent entries so numbering stays contiguous.

- [ ] **Step 2: Move I087 from Open → Fixed**

In `### Open — iOS stubs / no-ops / bugs` (or wherever I087 currently lives — search the file for `I087`), delete the row for I087.

In `### Fixed — verified in HEAD`, add a new row in the appropriate spot (entries are roughly chronological; placing after the I079 row is fine):

```markdown
| [I087](I087-failure-injection-no-auto-reconnect.md) | Connection doesn't auto-reconnect after failure-injection-style disconnect with unmapped platform error | `<FIX_SHA>` |
```

- [ ] **Step 3: Add I096 to Fixed**

Immediately after the I087 row, add:

```markdown
| [I096](I096-ios-nil-disconnect-error-to-unknown.md) | iOS `didDisconnectPeripheral` with `error: nil` produces `bluey-unknown` | `<FIX_SHA>` |
```

Use the same `<FIX_SHA>` for both. They came in together.

- [ ] **Step 4: Sanity-check the README parses**

```bash
head -130 docs/backlog/README.md | tail -50
```

Expected: Suggested order reads cleanly without I087/I091 references; tables are well-formed.

- [ ] **Step 5: Commit**

```bash
git add docs/backlog/README.md
git commit -m "chore(backlog): I087 fixed, I096 filed; drop attack-plan line item"
```

---

## Task 7: Final verification

- [ ] **Step 1: Inspect the commit graph**

```bash
git log --oneline main..HEAD
```

Expected: 5 commits in this order (oldest first):

```
fix(ios): nil-error disconnect maps to gatt-disconnected (I096)
chore(backlog): file I096 — iOS nil-error disconnect → bluey-unknown
chore(backlog): close I087 — fixed by I096 (nil-error disconnect)
chore(backlog): cross-reference I091 → I096 (different code path)
chore(backlog): I087 fixed, I096 filed; drop attack-plan line item
```

- [ ] **Step 2: Re-run Dart-side suite + analyzer one more time**

```bash
cd bluey && flutter test 2>&1 | tail -3
cd ..
flutter analyze 2>&1 | tail -3
```

Expected: tests pass, no new analyzer issues.

- [ ] **Step 3: Hand off to user**

Report:
- Branch: `fix/i096-nil-disconnect-error`
- 5 commits ahead of `main`
- One Swift change in `CentralManagerImpl.swift`, four documentation updates
- **Verification step is on the user's side: re-run the failure-injection stress test on iOS device. Expected outcome: no `BlueyPlatformException(bluey-unknown)` in the disconnect cascade; example app reconnects automatically.**

Do **not** push the branch. Per user preference, user handles git pushes.

---

## Self-review

**Spec coverage check:**

- Single-site fix in `CentralManagerImpl.swift` — Task 2.
- Honest TDD note about no Swift test target — captured in spec; plan reflects by having no Swift test step.
- Backlog hygiene: I096 filed (Task 3), I087 closed (Task 4), I091 cross-referenced (Task 5), README updated (Task 6).
- Diagnostic revert: implicit (branching off `main`, not the diagnostic branch).

**Placeholder scan:** `<FIX_SHA>` is the only placeholder; appears in Tasks 3, 4, 6 and is filled from Task 3 Step 1's command output.

**No-Swift-test rationale:** the spec's TDD section explicitly accepts on-device verification as the sufficient test for this small a fix, with a follow-up note about future Swift test infrastructure. This plan reflects that — no failing Swift test step.

**Remaining manual step:** user re-runs failure-injection stress test on iOS device. Plan flags this clearly in Task 7 Step 3.
