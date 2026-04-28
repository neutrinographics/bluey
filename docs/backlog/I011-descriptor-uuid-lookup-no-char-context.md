---
id: I011
title: Descriptor UUID lookup ignores characteristic context
category: bug
severity: critical
platform: android
status: fixed
last_verified: 2026-04-28
fixed_in: 73656b4
historical_ref: BUGS-ANALYSIS-#11, BUGS-ANALYSIS-ANDROID-A2
related: [I010]
---

## Symptom

The CCCD descriptor (`0x2902`) is present on every characteristic that supports notify/indicate. `findDescriptor(gatt, "2902")` always returns the first-discovered one. Enabling or disabling notifications on characteristic B silently toggles characteristic A's CCCD. Descriptor reads return the wrong descriptor's value.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:761-773` — nested `services → characteristics → descriptors` loop returns the first UUID match.

## Root cause

Same design bug as I010 (characteristic lookup): the lookup takes only a UUID, no characteristic context. This is strictly worse because CCCD is universal, so the probability of collision in any non-trivial device is high.

## Notes

Fix shape: thread `characteristicUuid` (and `serviceUuid`, per I010) into every descriptor Pigeon method — `readDescriptor`, `writeDescriptor`, and internally the CCCD write inside `setNotification`. The `setNotification` path is the highest-impact site because it's invoked on every notify subscribe/unsubscribe.

This is the single highest-severity open bug on Android. Probably the right moment to also fix I010 in the same PR, since they share the Pigeon-schema change.

## Resolution

Fixed in the bundled handle-rewrite via I088 (descriptor handles are now minted client-side and threaded through every descriptor Pigeon op, including the CCCD write inside `setNotification`; UUID-only descriptor lookup is gone). See `docs/superpowers/specs/2026-04-28-pigeon-gatt-handle-rewrite-design.md` for the full design and `docs/superpowers/plans/2026-04-28-pigeon-gatt-handle-rewrite.md` for the execution sequence.
