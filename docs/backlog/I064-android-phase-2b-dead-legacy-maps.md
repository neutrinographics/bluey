---
id: I064
title: "Legacy pending-op maps in `ConnectionManager` are dead code"
category: bug
severity: low
platform: android
status: open
last_verified: 2026-04-23
---

## Symptom

Cosmetic. After Phase 2a routed all GATT ops through `GattOpQueue`, the pre-Phase-2a maps (`pendingReads`, `pendingWrites`, `pendingDescriptorReads`, `pendingDescriptorWrites`, `pendingMtuRequests`, `pendingRssiReads`, `pendingServiceDiscovery`) and their corresponding timeout-runnable maps (`pendingReadTimeouts`, etc.) are declared but never written. The `cleanup()` and `cancelAllTimeouts()` methods still iterate and clear them, wasting cycles on empty maps.

The code comment at line 535 acknowledges this: *"Legacy map cleanup (unused after this task but declarations remain for Phase 2b to remove)"*.

## Location

Declarations: `bluey_android/.../ConnectionManager.kt:41-59`.

Cleanup iteration: `:420-446`, `:455-475`.

## Root cause

Phase 2a deliberately left the removal for Phase 2b to keep the Phase 2a diff focused on the queue introduction.

## Notes

Fix is mechanical: delete the dead declarations, the clear-loops in `cleanup()`, the prefix-cancel loops in `cancelAllTimeouts`, and the `cancelAllTimeouts` function itself if nothing else uses it.

What's *not* dead and must be preserved:

- `pendingConnections` — still live (keyed by deviceId, used for connect completion).
- `pendingConnectionTimeouts` — still live (wraps the connect timeout Runnable).
- `pendingServiceDiscoveryTimeouts`, `pendingMtuTimeouts`, `pendingRssiTimeouts` — these are also actually dead (service discovery, MTU, RSSI all go through queues now). Double-check before deleting.

Low severity. Can roll into the next meaningful ConnectionManager change.
