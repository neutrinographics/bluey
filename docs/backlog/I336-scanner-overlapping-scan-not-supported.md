---
id: I336
title: `BlueyScanner` does not support overlapping `scan()` calls
category: bug
severity: low
platform: domain
status: open
related: [I335]
---

## Symptom

`BlueyScanner.scan({List<UUID>? services, Duration? timeout})` does not
forbid overlapping calls and even maintains a `List<StreamController<ScanResult>>
_activeScanControllers` field (`bluey/lib/src/discovery/bluey_scanner.dart:52`),
suggesting multi-scan was intended. In practice the implementation
only supports one active scan at a time:

1. **Single platform subscription field.** `_platformSubscription` is a
   single `StreamSubscription?` field, not a list. A second `scan()`
   call overwrites it, orphaning the first platform subscription —
   the first scan's controller stays "open" but never receives further
   `ScanResult`s after the overwrite.

2. **Cancel-stops-everyone.** Per Convention 5 (PR #32, I335), the
   per-controller `onCancel` calls `stop()` unconditionally. With two
   active scans, cancelling either subscription stops the shared
   platform scan, silently starving the other.

3. **State machine fan-in.** `_setState(ScanState.scanning)` is called
   in three places driven by *any* scan call. A second `scan()` while
   one is already in flight would re-emit `starting → scanning`
   transitions even though the radio is already scanning, polluting
   `stateChanges` and the lifecycle events.

## Why this is a (minor) bug

The API surface invites overlapping calls — there's no
`StateError("scan already active")` guard, no return-existing-stream
behaviour, and the data structures hint at multi-scan support. Either
the implementation should actually multiplex, or the API should
explicitly forbid it.

## Suggested resolution

Pick one of:

- **Document single-scan-only and reject overlap.** Throw
  `StateError` (or a dedicated `ScanAlreadyActiveException`) from
  `scan()` when `_state` is not `stopped`. Remove the
  `_activeScanControllers` list in favour of a single nullable
  controller. Simpler implementation, matches what consumers
  realistically do (one scan at a time).

- **Properly multiplex.** Maintain a single shared platform
  subscription with a ref-count: only invoke `_platform.scan()` on
  the 0→1 transition of active controllers, and only call
  `_platform.stopScan()` on the N→0 transition. Each consumer gets
  its own filtered view; cancelling any one controller doesn't kill
  the platform scan unless it was the last. This matches the implicit
  semantics suggested by `_activeScanControllers`. Heavier, but
  honours the API shape the field hints at.

Single-scan-only is probably the right call given typical BLE
patterns — overlapping scans are rare in practice and the platform
side (Android `BluetoothLeScanner`, CoreBluetooth `CBCentralManager`)
doesn't have a natural multiplex either. The fix is mostly a guard +
field rename.

## Severity rationale

Low. No known consumer triggers this — `gossip_bluey` and the
`gossip_chat` dogfood app both serialize their scan calls. Flagged by
Codex on PR #32 as a P2 footgun.

## Notes

- Discovered during Codex review of PR #32. The reviewer's specific
  observation: with two active scans, cancelling either subscription
  now stops the platform resource unconditionally, leaving the other
  controller open but starved.
- Both resolution options are independent of the stream-conventions
  work that just shipped; the design conventions themselves are
  uniform either way.
