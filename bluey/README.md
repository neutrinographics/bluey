# bluey

A Flutter BLE (Bluetooth Low Energy) library providing a clean, platform-agnostic API for scanning, connecting, GATT operations, and peripheral/server mode.

## Logging

Bluey emits diagnostic events via `dart:developer.log` under five named loggers:

| Logger | Events |
|--------|--------|
| `bluey.connection` | connect / disconnect lifecycle, state transitions |
| `bluey.gatt` | per-operation start/complete/fail (read, write, discover, MTU, RSSI, notify) |
| `bluey.lifecycle` | heartbeat start, failure counter increments, peer-unreachable trip |
| `bluey.peer` | bluey-peer upgrade path (control-service discovery, serverId read) |
| `bluey.server` | server start, service registration, advertising state, central connect/disconnect |

Filter in DevTools by logger name; in Android logcat, filter for `flutter:`; in Xcode console, filter for the named-logger string.
