---
id: I334
title: `Bluey.stateStream` does not replay current value on subscription, leaving consumers stuck at `unknown` when the adapter never transitions
category: bug
severity: medium
platform: domain
status: fixed
last_verified: 2026-05-15
related: [I333]
---

## Resolution (2026-05-15)

Closed by the stream-conventions sweep on branch
`feature/stream-conventions`. Per Convention 2 of
`docs/superpowers/specs/2026-05-15-stream-conventions-design.md`,
every Type A stream in bluey now uses a `Stream.multi(isBroadcast: true)`
per-subscriber factory pattern that injects the cached current value
to each new subscriber before bridging the underlying broadcast
controller. (The plan originally proposed `StreamController.broadcast(onListen:)`,
but that only fires on the 0→1 subscriber transition — `Stream.multi`
is the correct primitive for per-subscriber replay.)

The convention applies uniformly across `Bluey.stateStream`,
`Connection.stateChanges`, `Connection.servicesChanges`,
`AndroidConnectionExtensions.bondStateChanges`,
`AndroidConnectionExtensions.phyChanges`, plus the new
`Scanner.stateChanges` and `Server.advertisingStateChanges`.

New subscribers receive the current value as their first emission;
the consumer-side `onListen` workaround in `gossip_bluey` can be
removed.

## Symptom

`Bluey.stateStream` is a plain `StreamController<BluetoothState>.broadcast()` (`bluey/lib/src/bluey.dart:94`). It emits only on platform transitions — never the current value at subscription time. Consumers that subscribe after construction therefore observe **nothing** until the adapter actually changes state.

This collides with three real-world scenarios:

1. **App launch with the adapter already on.** The platform plugin may seed `_currentState` synchronously from `_platform.currentState`, but no transition fires (the adapter hasn't changed), so `_stateController` stays silent. A consumer subscribing to `stateStream` to drive UI starts with no value — typically defaults to `unknown`.

2. **App launch with the platform's `currentState` returning `unknown`.** Same shape, worse outcome: bluey's `_currentState` is `unknown`, no transition ever fires (radio has been stable), and consumers stay at `unknown` indefinitely even though `Bluey.scanner()` / `Bluey.server()` / `Bluey.connect()` all work fine (because internally bluey's `_requireAdapterOn` reads `_currentState` after platform-stateStream events arrive, but external subscribers to `stateStream` never see those events if they happen before subscription).

3. **A consumer that wraps `stateStream` for its own UI** (e.g. `BlueyTransport.bluetoothStateStream` in gossip_bluey) must build a custom broadcast controller with `onListen` replay just to compensate. Every consumer ends up writing the same workaround.

Reproduced 2026-05-14 in the `gossip_chat` dogfood app on Android: scanning runs, devices are discovered, and the `Bluey` instance is internally healthy — but the app's UI shows "Bluetooth is off" because its `BluetoothAdapterState` snapshot is stuck at `unknown` (the value seeded at construction; no transition ever followed).

## Why this is a bluey bug

The semantics consumers want from "subscribe to the current Bluetooth state" almost universally include "tell me what it is *right now*, then keep me posted on changes." This is the same shape as Flutter's `ValueListenable`, RxDart's `BehaviorSubject`, and most state observables in the Flutter ecosystem.

Forcing every consumer to remember "subscribe, then also read `currentState`, and reconcile any race between the two" is a footgun. Several existing patterns in bluey already use `onListen` replay for similar reasons (e.g. `BlueyConnection`'s state surfaces post-I333) — `stateStream` is the outlier.

## Proposed fix

In `bluey/lib/src/bluey.dart` (around line 94), replace:

```dart
final StreamController<BluetoothState> _stateController =
    StreamController<BluetoothState>.broadcast();
```

with an `onListen` replay:

```dart
late final StreamController<BluetoothState> _stateController =
    StreamController<BluetoothState>.broadcast(
  onListen: () {
    // Replay the current value to new subscribers so they don't have
    // to wait for the next transition to learn the state. Matches the
    // pattern most consumers want from a state observable.
    if (!_stateController.isClosed) {
      _stateController.add(_currentState);
    }
  },
);
```

`_currentState` is already kept fresh by the platform's `stateStream` listener in the `Bluey` constructor, so the replay is always the most-recent observed value.

### Edge cases

- **Late initialization race.** The constructor reads `_platform.currentState` synchronously *then* attaches its platform listener. If the platform updates between those two lines, the cached value is stale until the next transition. This issue is not made worse by replay — it just becomes more *visible* because consumers actually see the (stale) value. Worth verifying both platform plugins (`BlueyAndroid`, `BlueyIos`) return a meaningful synchronous `currentState` after `BlueyPlatform.instance` is initialized. (I333's resolution notes confirm both maintain a `_cachedState` updated from `onStateChangedCallback`, so this should be solid.)

- **Multiple subscribers.** Each new listener gets the current value on subscription, which is what they want.

- **Error replay.** If the last platform emission was an error, the controller forwards it to the consumer's `addError`. The replay path adds a value, not the error — that's fine; transient errors should not stick to new subscribers.

## Consumer-side workaround (current state of the world)

In `gossip_bluey` (commit `b9a1744`), `BlueyPortImpl` builds its own `_adapterStateController` with `onListen` replay and forwards `_adapterState` (a cached map from `_bluey.currentState`) on subscription. This works but requires every consumer to do the same dance.

## Notes

- This is the second consumer-side `onListen` workaround in `gossip_bluey` driven by bluey-stream-without-replay; the other is the now-resolved I333 (live-instance invalidation). Replaying current values consistently across bluey's stream surfaces would let consumers stop reinventing the pattern.
- Sibling issue worth filing: `BlueyScanner.scan()` (in `bluey/lib/src/discovery/bluey_scanner.dart:117`) returns a `StreamController` with no `onCancel`, so consumers who cancel their subscription never trigger `_platform.stopScan()`. `gossip_bluey` worked around this in commit `6ab25a5` by holding the `Scanner` reference and calling `scanner.stop()` explicitly. Same shape of "stream contract that doesn't match Dart conventions for state/lifecycle"; consider auditing the other stream surfaces in bluey for similar gaps.
