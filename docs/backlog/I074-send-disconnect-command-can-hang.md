---
id: I074
title: "`sendDisconnectCommand()` can hang the entire `disconnect()` path"
category: bug
severity: high
platform: domain
status: open
last_verified: 2026-04-23
---

## Symptom

`BlueyConnection.disconnect()` awaits `_lifecycle.sendDisconnectCommand()` before proceeding to `_platform.disconnect(...)`. `sendDisconnectCommand` writes a single command byte to a control characteristic. If the peer is unresponsive — which is exactly the scenario where the user is usually trying to disconnect — the write awaits its platform timeout (10s default) before returning or throwing. The whole disconnect is blocked for 10 seconds.

## Location

`bluey/lib/src/connection/bluey_connection.dart:397` — the `await _lifecycle!.sendDisconnectCommand();` call inside `disconnect()`.

## Root cause

No timeout on the courtesy disconnect command, and no fallback path that proceeds with platform disconnect if the courtesy write fails. The write is treated as blocking.

## Notes

Fix sketch:

```dart
if (_lifecycle != null) {
  try {
    await _lifecycle!
        .sendDisconnectCommand()
        .timeout(const Duration(seconds: 1));
  } catch (_) {
    // Best-effort courtesy; proceed to platform disconnect.
  }
  _lifecycle!.stop();
}
```

The disconnect-command is a hint to the server, not a requirement. 1 second is generous; anything longer defeats the point of a soft-disconnect signal.

Related: the whole reason the courtesy command exists is that iOS `cancelPeripheralConnection` is unreliable (I202). Blocking on it undermines the purpose.
