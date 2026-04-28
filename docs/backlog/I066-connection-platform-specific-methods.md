---
id: I066
title: Cross-platform Connection interface declares platform-specific methods
category: bug
severity: high
platform: domain
status: fixed
last_verified: 2026-04-28
fixed_in: 73656b4
related: [I030, I031, I032, I035, I045, I065, I089, I200]
---

## Symptom

The `Connection` abstract interface declares `bond()`, `removeBond()`, `bondState`, `bondStateChanges`, `requestPhy()`, `txPhy`, `rxPhy`, `phyChanges`, `requestConnectionParameters()`, `connectionParameters` as if they were portable cross-platform methods. They aren't — Android stubs (I035) are silent successes; iOS doesn't expose these APIs at all (I200 documents the Apple limitation as wontfix).

The result is an API that lies about what the library can do. There is no compile-time signal of platform asymmetry. There is no runtime capability check (see I065). Calls succeed and return fake data, or throw obscure errors, depending on platform.

## Location

`bluey/lib/src/connection/connection.dart:205-287`. The "Bonding", "PHY", and "Connection Parameters" sections (line comments at 205, 237, 269) declare ten methods/getters/streams that are platform-asymmetric.

## Root cause

The interface was modeled after the union of features across platforms rather than the intersection (cross-platform) plus platform-specific extensions. This is the structural inverse of the right shape for a cross-platform abstraction.

## Notes

This is the architectural rewrite that resolves I030/I031/I032/I035/I045/I200 in one structurally-sound move. See I089 for the rewrite spec hand-off.

**Proposed shape:**

```dart
// Cross-platform — only methods that work everywhere
abstract class Connection {
  UUID get deviceId;
  ConnectionState get state;
  Stream<ConnectionState> get stateChanges;
  int get mtu;
  RemoteService service(UUID uuid);
  Future<List<RemoteService>> services({bool cache = false});
  Future<bool> hasService(UUID uuid);
  Future<int> requestMtu(int mtu);
  Future<int> readRssi();
  Future<void> disconnect();
  bool get isBlueyServer;
  ServerId? get serverId;

  // Platform-tagged extensions for asymmetric features
  AndroidConnectionExtensions? get android;
  IosConnectionExtensions? get ios;
}

// Returns null on non-Android platforms
abstract class AndroidConnectionExtensions {
  BondState get bondState;
  Stream<BondState> get bondStateChanges;
  Future<void> bond();
  Future<void> removeBond();

  Phy get txPhy;
  Phy get rxPhy;
  Stream<({Phy tx, Phy rx})> get phyChanges;
  Future<void> requestPhy({Phy? txPhy, Phy? rxPhy});

  ConnectionParameters get connectionParameters;
  Future<void> requestConnectionParameters(ConnectionParameters params);

  Future<void> requestConnectionPriority(ConnectionPriority priority);
  Future<void> refreshGattCache();
}

// Returns null on non-iOS platforms
abstract class IosConnectionExtensions {
  // Currently empty — iOS exposes no central-side equivalents.
  // Reserved for future iOS-specific features (e.g., L2CAP, channel-extras).
}
```

Usage:

```dart
final connection = await bluey.connect(device);

// Cross-platform code: works everywhere
await connection.requestMtu(517);

// Platform-specific code: explicit, type-safe, null-safe
await connection.android?.bond();
final phy = connection.android?.txPhy ?? Phy.le1m;
```

The type system now mirrors reality. Code that needs bonding has to explicitly opt into Android-only, which surfaces the asymmetry at review time.

This is a breaking change. Plan it as a major version bump, with a migration guide.

External references:
- Effective Dart, [Avoid defining unnecessary getters and setters](https://dart.dev/effective-dart/design#avoid-defining-unnecessary-getters-and-setters).
- Apple Accessory Design Guidelines, R8 (BLE) — confirms iOS does not expose central-side bond/PHY/conn-param control.
- `flutter_blue_plus` uses Boolean capability flags rather than typed extensions; it does not solve this problem cleanly. The proposed shape is novel within the Flutter BLE ecosystem.

## Resolution

Fixed in the bundled handle-rewrite via I089 (the `Connection` interface now declares only cross-platform members; bond/PHY/connection-parameters/connection-priority/refreshGattCache moved to `connection.android` of type `AndroidConnectionExtensions?`, with `connection.ios` reserved for symmetric future use). See `docs/superpowers/specs/2026-04-28-pigeon-gatt-handle-rewrite-design.md` for the full design and `docs/superpowers/plans/2026-04-28-pigeon-gatt-handle-rewrite.md` for the execution sequence.
