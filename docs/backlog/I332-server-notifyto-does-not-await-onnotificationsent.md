---
id: I332
title: `Server.notifyTo` returns before `onNotificationSent`; rapid notifications can be silently dropped on Android
category: bug
severity: high
platform: android
status: fixed
last_verified: 2026-07-06
fixed_in: aa588f1  # subsumed by I012 (per-central onNotificationSent FIFO)
related: [I331]
---

## Symptom

`Server.notifyTo(client, charUuid, data: ...)` returns its `Future` as soon as the platform call to `BluetoothGattServer.notifyCharacteristicChanged` returns, **not** when the platform fires `onNotificationSent` for that notification.

Android's GATT server contract requires waiting for the `onNotificationSent` callback before invoking `notifyCharacteristicChanged` again. Skipping the wait causes the controller queue to back up, and **any notification queued past the controller's per-connection limit is silently dropped** (the API returns `false`, but bluey's plugin does not propagate this back to Dart, and `notifyTo` resolves successfully regardless).

Reference: [Android Bluetooth Best Practices — Notification Queueing](https://developer.android.com/develop/connectivity/bluetooth/ble/connect-gatt-server#serve-data) and the `onNotificationSent` callback documentation.

## Observable behaviour

Reproduced 2026-05-06 in the `gossip_chat` dogfood app on a Pixel-class Android peripheral talking to an iOS central:

- Send rate: ~50 notifications/second (driven by gossip's anti-entropy + SWIM at the application layer; chunked into 20-byte writes by `gossip_bluey` due to I331).
- Symptom: the iOS central's `gossip_bluey` framing layer reports periodic ~200–500 byte recovery events ("frame decoder recovered from corruption ... discarded N bytes"). The discard counts are suspiciously chunk-aligned — typically integer multiples of 20.
- After several minutes: a connection drop on the Android side, with the link entering a state where `respondToWriteRequest` calls fail with `GATT_ERROR_INVALID_ATTR_LEN` (0x0A).

The chunk-aligned discard pattern is consistent with a few specific notifications having been silently dropped at the controller layer — not with byte-level garbling, which would produce randomly-aligned discard sizes.

## Location

- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt` — `notifyCharacteristicChanged` is called and the result returned to Dart, but `onNotificationSent` is not awaited before resolving the operation.
- `bluey/lib/src/gatt_server/bluey_server.dart` — `notifyTo` builds a Future from the platform call's return value; no per-client serialization or `onNotificationSent` join.

## Proposed fix

`Server.notifyTo` must serialize per-client notifications and join the `onNotificationSent` event for each call before resolving the Future:

```kotlin
// Pseudocode
suspend fun notifyTo(client: Client, charUuid: UUID, data: ByteArray) {
  perClientMutex(client.id).withLock {
    val ok = gattServer.notifyCharacteristicChanged(...)
    if (!ok) throw NotifyQueueFullException(...)
    // Wait for onNotificationSent for THIS client before unlocking.
    awaitNotificationSent(client.id)
  }
}
```

iOS doesn't have a strict equivalent — `peripheralManager(_:didReceiveWrite:)` flow is acknowledged at the ATT layer — so the iOS path can resolve immediately. The fix is Android-specific.

## Why high severity

This is the proximate cause of observable corruption in `gossip_bluey`'s real-world traffic. Even with framing-level recovery (which `gossip_bluey` ships), the corruption costs gossip a re-sync round (~1s) per drop, plus the consumer accumulates `bytesDiscarded` metrics. With this fix, notifications would be reliably delivered (per BLE LL guarantees), and the framing-level recovery would only catch genuinely rare events (cable-yanked-mid-connection, etc.).

Combined with I331 (smaller chunks than necessary), the queue overflow is much easier to hit. Fixing either one alone reduces but doesn't eliminate the symptom; fixing both should make the failure mode disappear in normal operation.

## Notes

- Investigate whether `Connection.write(withResponse: false)` on the central side has the analogous issue — Android's `BluetoothGatt.writeCharacteristic` for `WRITE_TYPE_NO_RESPONSE` similarly requires waiting for `onCharacteristicWrite` before the next call. Worth a separate ticket if confirmed.
- A test that sends N notifications back-to-back without artificial delay and asserts all N are received on the central side (using a fake/mock platform) would catch regressions.
