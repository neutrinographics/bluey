# Transport-address value objects (`DeviceAddress` / `ClientAddress`)

- **Date:** 2026-05-29
- **Status:** Approved (design)
- **Related:** I337 (client id / disconnections mismatch); supersedes the point-fix proposed there.

## Problem

bluey identifies a remote BLE endpoint with a mix of two representations that
don't agree, and the disagreement is a real consumer-facing bug (I337).

The remote's identity is exposed publicly **twice** in each context:

| Concept | Context | Today |
|---|---|---|
| Remote peripheral we discovered / connected to | Discovery / Connection | `Device.id : UUID` (lossy) **and** `Device.address : String`; `Connection.deviceId : UUID` |
| Remote central that connected to our server | GATT-Server | `Client.id : UUID` (lossy) **and** `clientId : String` (events, lifecycle, `disconnections`) |
| Stable protocol identity | Peer | `ServerId` (value object — already correct) |

The `UUID`-typed views are produced by **lossy synthesis** from the raw
platform string, in three places using **two different algorithms**:

- `src/shared/device_id_coercion.dart` (`deviceIdToUuid`) — strips colons,
  lowercases, zero-pads the MAC as hex to 32 chars. Used by `_mapDevice`.
- `src/discovery/bluey_scanner.dart:405` — a duplicated local copy of the same.
- `src/gatt_server/bluey_server.dart:1041` (`Client.id`) — a *different*
  algorithm: ASCII-encodes the string's code units, pads/truncates to 16 bytes,
  hex-encodes. For a 17-char MAC the last byte is silently dropped.

`device_id_coercion.dart`'s own doc already declares this a workaround and names
the fix: *"a typed device-identifier value object that can hold either form
natively."* This design executes that fix.

### The I337 failure

A consumer bridging `Server.peerConnections` (keyed by
`peerClient.client.id.toString()`) and `Server.disconnections` (a raw `String`)
finds the two values don't match, so disconnect bookkeeping leaks and legitimate
reconnects are later rejected as duplicates.

**Platform scope correction:** the native side already lowercases the iOS
identifier for both `PlatformDevice.id` and `PlatformCentral.id`
(`CentralManagerImpl.swift`, `PeripheralManagerImpl.swift`). So on iOS the raw
platform string is an already-normalized lowercase UUID, and `Client.id`'s
first branch re-normalizes it to the same value — **the mismatch is Android-only**.
I337's "platform: both" claim does not reproduce on iOS. The fix is still
worthwhile: it deletes the lossy synthesis and unifies the types so the bug
becomes structurally impossible.

## Model

A remote's transport identity becomes a **value object that holds the native
platform string directly** — one type per bounded context — and the lossy
`String → UUID` synthesis is deleted entirely.

```
Platform-Interface (wire vocabulary) ── String ids on Pigeon DTOs
   (PlatformDevice.id, PlatformCentral.id) — UNCHANGED
        │  wrap at inbound seam / unwrap .value at outbound seam (cf. AttributeHandle)
        ▼
Domain
   Discovery / Connection  ──  DeviceAddress
   GATT-Server             ──  ClientAddress
   Peer                    ──  ServerId        (unchanged)
```

### Why this naming

- **`-Address` suffix, not `-Id`:** "address" honestly signals "opaque
  platform-level identifier, don't parse"; "id" is the word that let it
  masquerade as a UUID. The suffix is shared so the two read as the same *kind*
  of handle.
- **`Device` / `Client` nouns, not `Server` / `Client`:** every GATT link is a
  client/server relationship, and the *relationship-accurate* pair would be
  `ServerAddress` (remote server we connected to) / `ClientAddress` (remote
  client that connected to us). But `Server` is already this library's *local*
  hosted role (`bluey.server()`, the `Server` class) and `ServerId` is already
  the remote peer's protocol identity — so `ServerAddress` would collide and
  require renaming our own role. `Device` / `Client` are the nouns each context
  already uses everywhere; keeping them is consistent and low-churn. The
  asymmetry is honest: you *discover devices* (possibly before any connection),
  but you *get connected-to by clients*.
- The two are **not** two ends of one wire in general — they address different
  remotes on independent links (one outbound, one inbound), coinciding only when
  one peer both scans and advertises. The symmetry is **role-duality**
  ("same handle, opposite direction"), which the shared suffix + mirrored docs
  convey.

### Value-object shape

Both follow the `ServerId` template, in their context-local directories
(`src/discovery/device_address.dart`, `src/gatt_server/client_address.dart`):

```dart
@immutable
class DeviceAddress {
  final String value;
  const DeviceAddress(this.value);          // no validation; opaque

  String toShortString() => value.length <= 8 ? value : value.substring(0, 8);

  @override
  bool operator ==(Object other) =>
      other is DeviceAddress && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}
```

`ClientAddress` is structurally identical with a different type name.

Deliberately **format-agnostic** — unlike `ServerId` (which validates UUID-v4),
these accept any opaque platform string (MAC, CBPeer/CBCentral UUID, future
forms). No `toUuid()` / `asUuid` escape hatch — that would resurrect the lossy
synthesis through the back door. `const` constructor kept so fixtures can be
`const`. `toShortString()` is display-only ("first 8 chars"), matching the
existing `_shortId` log helper.

Class docs (directional positioning, cross-referencing each other):

```dart
/// Opaque, platform-assigned address of a remote BLE **peripheral that this
/// device discovered or reached out to** — the *outbound* direction, in which
/// the local role is GATT **client** and the remote is the GATT server.
///
/// Sourced at the scan/connection seam from `PlatformDevice.id`: the MAC
/// address on Android, the `CBPeripheral.identifier` UUID string on iOS. The
/// format is platform-specific and opaque — never parse it.
///
/// Mirror of [ClientAddress], which addresses a remote central that connected
/// *inbound* to our local `Server`. Both wrap the same kind of platform
/// string; the distinct types keep the communication direction legible and
/// prevent accidental cross-assignment. The two coincide only when one peer
/// both scans and advertises (see `isClientConnected`).
class DeviceAddress { … }

/// Opaque, platform-assigned address of a remote BLE **central that connected
/// inbound to our local `Server`** — the *inbound* direction, in which the
/// local role is GATT **server** and the remote is the GATT client.
///
/// Sourced at the GATT-server seam from `PlatformCentral.id` / `centralId`:
/// the MAC address on Android, the `CBCentral.identifier` UUID string on iOS.
/// The format is platform-specific and opaque — never parse it.
///
/// This is the value emitted on `Server.disconnections` and carried by the
/// server-side events, so it is the stable key for bridging the
/// `peerConnections` and `disconnections` streams (this is the fix for I337).
///
/// Mirror of [DeviceAddress], which addresses a remote peripheral we
/// discovered/connected to *outbound*.
class ClientAddress { … }
```

## The seam

Rule (mirrors `AttributeHandle`, "unwrapped to the wire-level int only at the
Pigeon boundary"): **the raw platform `String` exists only between the Pigeon
DTO and the immediate wrap/unwrap. Everything inside the domain holds the value
object.**

- **Inbound (platform → domain):** wrap immediately. `_mapDevice` / scanner →
  `DeviceAddress(platformDevice.id)`; server connect/disconnect/request
  callbacks wrap `platformCentral.id` / `req.centralId` into `ClientAddress`.
  `device_id_coercion.dart` is **deleted**.
- **Outbound (domain → platform):** unwrap `.value` at the call site
  (`notifyCharacteristicTo(client.address.value, …)`, connection connect/
  disconnect, etc.).
- **Internal:** the value object is the currency. `BlueyServer._connectedClients`
  → `Map<ClientAddress, BlueyClient>`, `_identifiedPeerClientIds` →
  `Set<ClientAddress>`, and **`LifecycleServer` converts to `ClientAddress`
  throughout** (`onClientGone`, `onPeerIdentified`, `cancelTimer`,
  `recordActivity`, `requestStarted/Completed`, internal `_clients` map). This
  is the largest single chunk of churn and is what makes I337
  **un-reintroducible**: no raw `String` remains in domain code to leak onto
  `disconnections`.

The platform-interface package (`PlatformDevice.id`, `PlatformCentral.id`,
Pigeon DTOs) stays `String` — untouched. Translation is the domain's job.

## Breaking-change policy

**Clean break, no deprecation shims.** This is a pre-1.0 workspace monorepo; the
consumers (example app, gossip apps) are in our control, so the compiler is the
migration tool. Shims would keep the lossy code on life support.

## Sequence (each step independently shippable, suite green)

1. **Discovery — `DeviceAddress`.** New value object + docs; delete
   `device_id_coercion.dart`; `_mapDevice`/scanner wrap `PlatformDevice.id`
   directly; collapse `Device` to a single `Device.address : DeviceAddress`
   (drop `Device.id`); move `Device` entity equality onto `address`.
2. **Connection — `Connection.deviceId` → `Connection.deviceAddress : DeviceAddress`**
   plus the connection/GATT events carrying it (rename `deviceId` →
   `deviceAddress` for consistency with the new type); unwrap `.value` at
   outbound platform calls.
3. **GATT-Server — `ClientAddress`.** New value object + docs; `LifecycleServer`
   and `BlueyServer` internals → `ClientAddress`; `Map<ClientAddress, BlueyClient>`;
   event `clientId` fields → `clientAddress : ClientAddress`;
   `disconnections : Stream<ClientAddress>`; `isClientConnected(ClientAddress)`;
   wrap inbound, unwrap `.value` outbound.
4. **`Client.id` → `Client.address : ClientAddress`.** Trivial swap; now equal
   to the `disconnections` value by construction — I337 dissolves with no
   special-casing.

## Equality, dedup & testing

- **Equality/dedup:** `Device` entity equality moves from the synthetic UUID to
  `DeviceAddress` (equality-by-value on the real platform string) — strictly
  more correct for scan-result dedup. `BlueyClient` identity is its
  `ClientAddress`.
- **TDD (Red → Green → Refactor) per step.** Each value object gets a unit test:
  equality, `toString`, `toShortString`, and opacity (accepts MAC *and* UUID
  forms unchanged, no transformation). Then a regression test per affected
  surface.
- **Headline regression — the I337 bridge test:** emit a `peerConnections` entry
  and a `disconnections` entry for the same Android-MAC client and assert
  `client.address == disconnectionAddress`. Fails on `main` today; passes after
  step 4.
- The existing 543-test suite is the safety net for the clean-break type swaps.
  `flutter analyze` + `flutter test` green after every step.

## Out of scope

- Renaming the `Server` / `Device` vocabulary to allow a `ServerAddress` naming.
- Any change to `ServerId` or the peer protocol layer.
- Platform-interface / Pigeon DTO types (stay `String`).
