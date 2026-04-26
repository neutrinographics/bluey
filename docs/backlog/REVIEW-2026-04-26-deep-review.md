---
title: Deep Review (2026-04-26) — Backlog Suggestions
review_origin: "External code review conducted via Claude.ai chat session"
review_date: 2026-04-26
review_scope: |
  Full read-through of bluey, bluey_platform_interface, bluey_android,
  bluey_ios, and the example app. Focused on platform asymmetry,
  threading, error translation, identity, lifecycle protocol, and
  testing infrastructure. Compared against the BLE platform-divergence
  reference produced earlier in the session.
---

# Deep Review (2026-04-26) — Backlog Suggestions

## Purpose & framing

This document captures findings from a deep external review of the Bluey
codebase. **Every entry here is a suggestion, not a directive.** The review
was conducted by reading source files in isolation, without running the
code, the tests, or the example app. There is therefore an irreducible
risk that any given finding is wrong — the code may have already addressed
it in a way the reviewer didn't see, or the reviewer's understanding of
the platform behavior may be incomplete.

**The intended workflow for this document is:**

1. The local Claude CLI session reads this document.
2. For each suggested finding, the CLI **verifies the issue against HEAD**
   by reading the cited file/lines and confirming the described behavior.
3. If verified, the CLI creates or updates the backlog entry as suggested.
4. If the verification fails (the code already does the right thing, or
   the diagnosis was incorrect), the CLI either skips the entry or notes
   the discrepancy in a `verification:` section.

Where the reviewer's confidence is low, the entry is explicitly marked
`confidence: low` — those entries especially need verification before
acting on.

## Pending in-flight branch — peer-silence

> **Update 2026-04-26 (post-review).** After the initial review, the
> reviewer was shown a substantial in-flight branch (`peer-silence`)
> that has not yet merged to main. The branch:
>
> - Replaces `LivenessMonitor` (count-based: N consecutive failures
>   trip the threshold) with `PeerSilenceMonitor` (time-based: a death
>   watch arms on first failure, fires after a fixed
>   `peerSilenceTimeout`, cancels on any successful exchange).
> - Implements the I097 fix: `_runGattOp` now wraps every user GATT op
>   with `markUserOpStarted` / `markUserOpEnded` / `recordActivity` /
>   `recordUserOpFailure` so user-op outcomes feed the silence detector
>   alongside heartbeat probes. While `_pendingUserOps > 0`, scheduled
>   probes defer — the in-flight op is itself a peer probe.
> - Passes lifecycle as a getter (`() => _lifecycle`) into
>   `BlueyRemoteCharacteristic` / `BlueyRemoteDescriptor` so
>   characteristics built during initial service discovery (before
>   `upgrade` runs) pick up the lifecycle once it's installed.
>
> **What the CLI should do when verifying this document against HEAD:**
>
> 1. **Check whether the peer-silence branch has merged.** If it has,
>    `LivenessMonitor` no longer exists; references to it in any of
>    the entries below are about its replacement. Several existing
>    backlog entries change status:
>    - **I097 → fixed** (the explicit fix is the new monitor + user-op
>      accounting).
>    - **I077, I078** were already fixed pre-branch; unchanged.
> 2. **The new `_runGattOp` is more sophisticated.** It now does both
>    typed exception translation *and* lifecycle accounting through one
>    funnel. The I099 rewrite suggestion (replacing `_wrapError`
>    string-matching) must preserve the lifecycle-accounting hook —
>    see I099 notes for specifics.
> 3. **The peer-silence branch introduced two minor new findings**
>    captured below as a single new entry (default-value choice of
>    `peerSilenceTimeout`, racing OS supervision timeout). These
>    only apply once the branch has merged.
> 4. **No findings in this document are invalidated by the branch.**
>    The branch is laser-focused on lifecycle policy + I097; the rest
>    of the deep review (Pigeon schema, Android threading, error
>    wrapping, capability gating, iOS server-side issues, dead events)
>    is orthogonal.

## Confidence levels

Each suggested finding is annotated with one of:

- **`confidence: high`** — Reviewer read the code at the cited location,
  traced the relevant data flow, and is confident the issue is real as
  described. Verification should be quick (read the file, confirm).
- **`confidence: medium`** — Reviewer read the cited location but did
  not trace every data path. The issue is likely real but a corner case
  may invalidate the diagnosis. Verification should include reading
  adjacent code paths.
- **`confidence: low`** — Reviewer believes there is an issue but did
  not trace it sufficiently to be sure. Treat these as "investigate"
  rather than "fix."

## How the CLI should use this document

For each entry below, in sequence:

1. **Read the cited file at the cited line range.**
2. **Confirm the described symptom is reproducible from the code as
   currently committed.** If unsure, read related test files and
   recent commits affecting the file.
3. **Cross-reference any existing backlog entries** named in the
   `related:` field to ensure no duplication.
4. **If verified:**
   - For new entries: create the file at `docs/backlog/I{ID}-{slug}.md`
     with the YAML frontmatter and prose as suggested.
   - For updates: edit the existing entry per the update notes.
5. **If not verified:** add a brief note here in this document under
   "Verification log" explaining what was found instead, and skip
   the entry.

When a finding overlaps with an existing entry, prefer **updating the
existing entry** over creating a new one. The reviewer's notes flag
these explicitly.

## Summary table

| Suggested ID | Title | Cluster | Severity | Confidence | Disposition |
|---|---|---|---|---|---|
| I016 | iOS server `characteristics` dict keyed by UUID alone | iOS | high | high | new |
| I035 | Android Dart-side bonding/PHY/conn-param stubs return silent success | Android conn stubs | high | high | new |
| I045 | iOS `disconnectCentral` is a lying no-op | iOS | medium | high | new |
| I046 | iOS `getMaximumWriteLength` implemented but not exposed via Pigeon | iOS | medium | high | new |
| I047 | iOS `pendingWriteRequests` batch responds only to first request | iOS | medium | **low** | new |
| I048 | iOS `CBManagerOptionRestoreIdentifierKey` not set; no state restoration | iOS | medium | high | new |
| I054 | Dead event types in `events.dart` (CharacteristicReadEvent et al.) | cross-platform | low | high | new |
| I055 | `PeerDiscovery` doesn't filter scan by control-service UUID | cross-platform | medium | high | new |
| I056 | `PeerDiscovery` probe-connect has no timeout | cross-platform | medium | high | new |
| I057 | MAC-to-UUID coercion duplicated in two places | cross-platform | low | high | new |
| I058 | `BlueyServer.startAdvertising` drops user's `mode` parameter | cross-platform | medium | high | new |
| I059 | `BlueyServer.removeService` is fire-and-forget (unawaited) | cross-platform | low | high | new |
| I065 | `Capabilities` matrix doesn't gate any production code path | cross-platform | medium | high | new |
| I066 | `Connection` interface exposes platform-specific methods cross-platform | cross-platform / arch | high | high | new (rewrite) |
| I067 | Two-state `ConnectionState` lacks "linked vs ready" distinction | cross-platform | medium | medium | new |
| I068 | `BlueyEventBus` missing lifecycle/heartbeat events | cross-platform | low | high | new |
| I069 | `FakeBlueyPlatform.capabilities` hardcoded; tests don't exercise gating | cross-platform | medium | high | new |
| I088 | Rewrite Pigeon GATT schema to carry service/char context | cross-platform / arch | critical | high | new (rewrite) |
| I098 | Rewrite Android ConnectionManager threading + disconnect lifecycle | Android / arch | high | high | new (rewrite) |
| I099 | Rewrite `Bluey._wrapError` and peer-error-wrapping to typed catch ladder | domain / arch | high | high | new (rewrite) |
| I017 | Default `peerSilenceTimeout` value choice and supervision-timeout race | cross-platform | low | medium | new (peer-silence-branch dependent) |
| I010 | Add iOS server-side mirror as additional location | iOS | — | high | **update** |
| I040 | Refine root cause: backpressure misclassified as failure, not just "no retry" | iOS | — | high | **update** |
| I090 | Extend scope: bond/removeBond/requestPhy/requestConnectionParameters bypass too | domain | — | high | **update** |

Total: 18 new entries, 3 update notes, 4 architectural rewrites.

> **ID allocation note (updated)**: The reviewer chose IDs based on the
> cluster conventions documented in `docs/backlog/README.md` ("ID allocation"
> section). Several gaps exist within clusters (e.g., I045-I049 for iOS,
> I016-I019 for Android native bugs); the assignments below try to
> respect cluster boundaries.
>
> The post-review addition (I017) doesn't fit cleanly: the cross-platform
> cluster (I050-I099) is fully assigned by the existing backlog plus this
> briefing's other entries, and the finding is domain-level rather than
> Android-native. I017 is suggested as the next available numeric slot;
> the CLI should either accept the slight cluster-mismatch or pick an
> alternate ID and note it in the verification log.
>
> The CLI should also adjust IDs if any chosen number is already taken in
> HEAD that wasn't in the reviewer's snapshot.

---

## NEW ENTRIES — to verify and create

### I016 — iOS server `characteristics` dict keyed by UUID alone

```yaml
---
id: I016
title: iOS server `characteristics` dict keyed by UUID alone (mirror of I010)
category: bug
severity: high
platform: ios
status: open
last_verified: 2026-04-26
related: [I010, I011]
---
```

**Confidence: high.** Reviewer confirmed via direct read.

**Symptom.** `PeripheralManagerImpl` stores hosted characteristics in a
flat `[String: CBMutableCharacteristic]` map keyed by characteristic
UUID. If a server hosts two services that both define a characteristic
with the same UUID, the second `addService` call overwrites the first
characteristic in the lookup table. Subsequent operations on that UUID
(e.g., `notifyCharacteristic`) target the wrong characteristic, silently.

**Location.** `bluey_ios/ios/Classes/PeripheralManagerImpl.swift:18, 53`.

**Root cause.** Same dimensional error as I010/I011 on the central side,
mirrored on the server side. Lookup key is a 1-tuple `(charUuid)` when
it should be a 2-tuple `(serviceUuid, charUuid)`.

**Notes.** The fix is bound up with I088 (Pigeon-schema rewrite for GATT
identity context). Any redesign that adds `serviceUuid` to the wire
schema for client-side reads/writes/notifies should also propagate
service context through the server-side hosted-characteristic table.

In the interim, a defensive workaround on the iOS side: change
`characteristics: [String: CBMutableCharacteristic]` to
`characteristics: [String: [String: CBMutableCharacteristic]]` keyed
by `(serviceUuid, charUuid)`. The Pigeon schema doesn't need to change
yet — server-internal calls already know the service context at
`addService` time.

**External references.**
- BLE Core Specification 5.4, Vol 3, Part G, §3.1: services and
  characteristics, including the explicit allowance of duplicate
  characteristic UUIDs across services.
- Apple `CBMutableService.characteristics` (the CoreBluetooth-side
  ownership model): https://developer.apple.com/documentation/corebluetooth/cbmutableservice

---

### I017 — Default `peerSilenceTimeout` value choice and supervision-timeout race

> **Branch dependency.** This finding only applies once the
> `peer-silence` branch has merged. If the branch is still pending,
> defer this entry. See "Pending in-flight branch — peer-silence" near
> the top of this document.

```yaml
---
id: I017
title: Default `peerSilenceTimeout` (20s) is internally inconsistent and races Android supervision timeout
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-04-26
related: [I097]
---
```

**Confidence: medium.** The reviewer read the peer-silence diff but did
not test the racing behavior empirically. The "races OS supervision
timeout" claim is theoretically motivated; verification would benefit
from on-device observation of which path fires first under genuine
link loss (force-out-of-range, kill battery, etc.).

**Symptom (two related concerns).**

**(a) Internal default mismatch.** The library-level default for
`peerSilenceTimeout` in `Bluey.connect`, `Bluey.peer`, `BlueyConnection`
constructor, and `_BlueyPeer.connect` is **20 seconds**. The example
app's `ConnectionSettings` uses **30 seconds** as its default. Consumers
reading the docstring on `Bluey.connect` see one value; consumers
copying the example app's settings cubit see another.

**(b) Racing OS supervision timeout.** The Android default link
supervision timeout is approximately 20 seconds (computed as
`supervisionTimeout = 0x0080 × 10ms = 2048 supervision events at the
default 10ms parameters`, configurable via the link layer but rarely
overridden). When the BLE link genuinely fails, the OS-level supervision
timeout fires at ~20s and the platform reports `STATE_DISCONNECTED`,
which already triggers tear-down through a separate path (the
`connectionStateStream` listener in `BlueyConnection`).

If the silence detector also fires at 20s, the two detection paths race.
Usually the OS path wins because it tears down the platform connection
synchronously (which drains the queue with `gatt-disconnected` errors,
which feeds the silence detector to convergence). But the timing
coincidence isn't ideal — a slightly longer silence-detector default
gives the OS room to act first, simplifying the failure narrative for
consumers and reducing the chance of "double-disconnect" events on
the connection state stream.

**Location.**
- Library defaults (`peer-silence` branch):
  - `bluey/lib/src/bluey.dart` — `connect(...)`, `peer(...)`,
    `_upgradeIfBlueyServer(...)`: `peerSilenceTimeout = const Duration(seconds: 20)`.
  - `bluey/lib/src/connection/bluey_connection.dart` — constructor
    default `peerSilenceTimeout = const Duration(seconds: 20)`.
- Example app default:
  - `bluey/example/lib/features/connection/domain/connection_settings.dart` —
    `peerSilenceTimeout = const Duration(seconds: 30)`.

**Root cause.** Independent default-value choices that drifted apart
during the peer-silence branch. The 20s figure was likely chosen as
"shorter than the heartbeat interval doubled" or similar; the example
app's 30s figure was likely chosen as "longer than typical user-op
timeouts." Neither default explicitly considered the OS supervision
timeout as an upstream constraint.

**Notes.** Suggested fix:

1. **Reconcile defaults.** Pick one value and use it consistently across
   library and example. The reviewer's recommendation: **30 seconds**.
   Rationale:
   - Conservative against false positives during transient link
     congestion on stressed Android devices.
   - Strictly longer than the Android default supervision timeout
     (~20s), so the OS path has room to fire first on genuine link
     loss.
   - Aligned with iOS's longer effective supervision timeout (Apple's
     recommended range for connection supervision is 2-6 seconds, but
     the OS may extend this for stability).

2. **Document the rationale.** The doc-comment on
   `Bluey.connect`'s `peerSilenceTimeout` parameter should explicitly
   note that the value should be chosen to exceed the platform
   supervision timeout, with a one-sentence pointer to the BLE Core
   Spec section on supervision timeout.

3. **Optional: clamp to a minimum.** Constructor-time assertion or
   warning if `peerSilenceTimeout < Duration(seconds: 10)` — values
   below the supervision timeout actively undermine the design
   (silence detector fires before the OS can disambiguate transient
   from terminal).

**Verification steps for the CLI session.**

1. Confirm the peer-silence branch has merged. If not, defer this entry.
2. Read the four library default sites listed above and confirm they
   all currently say `Duration(seconds: 20)`. (The diff showed they do.)
3. Read the example app's `ConnectionSettings` default. (The diff showed
   `Duration(seconds: 30)`.)
4. Decide on the canonical default value and apply consistently.

**External references.**
- Bluetooth Core Specification 5.4, Vol 6 (Low Energy Controller),
  Part B, §4.5.2: Link Supervision Timeout. Defines the LL-level
  semantics; the AOSP default for `BTM_BLE_CONN_TIMEOUT_DEF` is
  approximately 2000 (× 10ms = 20s).
- Apple's `CBPeripheral` connection parameters discussion in the
  Accessory Design Guidelines (R8 BLE), Connection Parameters
  section: recommended supervision timeout 2-6 seconds for low-latency
  use cases, but iOS may negotiate longer.
- Existing entry I097 — the immediate predecessor of the peer-silence
  branch's user-op-accounting work.

---

### I035 — Android Dart-side bonding/PHY/connection-parameter stubs return silent success

```yaml
---
id: I035
title: Android Dart-side bonding/PHY/connection-parameter methods return silent success
category: no-op
severity: high
platform: android
status: open
last_verified: 2026-04-26
related: [I030, I031, I032, I033, I034]
---
```

**Confidence: high.** Reviewer read the entire stub block.

**Symptom.** `connection.bond()` on Android completes successfully with
no error, but does not initiate a bond. `connection.bondState` returns
`BondState.none` permanently. `connection.bondStateChanges` is an empty
stream that never emits. `connection.requestPhy(...)` resolves successfully
but does not send the HCI command. `connection.connectionParameters`
returns hardcoded default values regardless of the actual link state.

This is **worse** than throwing `UnimplementedError`: the API silently
lies. A consumer reading the docstring on `Connection.bond()` ("This will
start the bonding process") sees the future complete and assumes
bonding succeeded. They then attempt to read an encryption-required
characteristic, which fails — and the failure is opaque.

**Location.** `bluey_android/lib/src/android_connection_manager.dart:211-281`.

```dart
// Line 223-225, representative example:
Future<void> bond(String deviceId) async {
  // TODO: Implement when Android Pigeon API supports bonding
}
```

All ten stub methods (`getBondState`, `bondStateStream`, `bond`,
`removeBond`, `getBondedDevices`, `getPhy`, `phyStream`, `requestPhy`,
`getConnectionParameters`, `requestConnectionParameters`) follow this
pattern — return hardcoded defaults or empty streams, do nothing.

**Root cause.** The Pigeon schema (`bluey_android/pigeons/messages.dart`)
doesn't declare these methods, so the Dart-side adapter has nothing to
delegate to. The TODO comments correctly identify the missing piece, but
the chosen placeholder behavior (silent success) is the wrong choice for
a stub: it makes the bug invisible to consumers.

**Notes.** Two-stage fix:

**Stage A (immediate, ~1 hour, removes the silent-lie mode):** change every
stub to throw `UnsupportedOperationException(operation, 'android (not yet implemented)')`
until the real implementation lands. The cross-platform `Capabilities` matrix
already has `canBond: true` for Android — that's the production lie. If
the user calls `bond()` and it throws, they can at least catch and react.

```dart
// Stage A pattern:
Future<void> bond(String deviceId) async {
  throw UnsupportedOperationException('bond', 'android (not yet implemented)');
}
```

Concomitantly, set `Capabilities.android` to `canBond: false` etc. until
real implementations land — `capabilities` should be the truth, not the
aspiration.

**Stage B (proper fix, weeks):** add Pigeon methods for bond/PHY/connection-priority,
implement the Kotlin side using `BluetoothDevice.createBond()`,
`BluetoothGatt.setPreferredPhy(...)`, and `BluetoothGatt.requestConnectionPriority(...)`.
Wire up callbacks for bond state changes (BroadcastReceiver on `ACTION_BOND_STATE_CHANGED`)
and PHY changes (`onPhyUpdate` / `onPhyRead` in the gatt callback).

This issue is the necessary precondition for I030, I031, I032, I033, I034.
Mark those as `blocks: [I035]` or treat I035 as an umbrella for them.

**External references.**
- Android `BluetoothDevice.createBond()`:
  https://developer.android.com/reference/android/bluetooth/BluetoothDevice#createBond()
- Android `BluetoothGatt.setPreferredPhy(int, int, int)`:
  https://developer.android.com/reference/android/bluetooth/BluetoothGatt#setPreferredPhy(int,%20int,%20int)
- Android `BluetoothGatt.requestConnectionPriority(int)`:
  https://developer.android.com/reference/android/bluetooth/BluetoothGatt#requestConnectionPriority(int)
- Bond state broadcast `ACTION_BOND_STATE_CHANGED`:
  https://developer.android.com/reference/android/bluetooth/BluetoothDevice#ACTION_BOND_STATE_CHANGED
- Martijn van Welie's *Making Android BLE Work — Part 4* on bonding:
  https://medium.com/@martijn.van.welie/making-android-ble-work-part-4-72a0b85cb442

---

### I045 — iOS `disconnectCentral` is a lying no-op

```yaml
---
id: I045
title: iOS `disconnectCentral` returns success without disconnecting the central
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-04-26
related: [I207]
---
```

**Confidence: high.** Apple's `CBPeripheralManager` does not expose any
API to force-disconnect a central; this is well-documented platform
behavior.

**Symptom.** `server.disconnectCentral(centralId)` on iOS resolves
successfully and the central is removed from the server's local
`centrals` and `subscribedCentrals` tracking. The actual BLE link
remains connected at the OS level. The central can continue reading,
writing, and receiving notifications — the server just no longer
tracks it. From the central's perspective, nothing happened.

The consumer of the Server API gets a successful Future, treats the
central as gone, and may free associated resources. Subsequent
operations from that central appear as "ghost" interactions from an
unknown peer.

**Location.** `bluey_ios/ios/Classes/PeripheralManagerImpl.swift:176-189`.

**Root cause.** CoreBluetooth's `CBPeripheralManager` provides no method
to terminate an active central connection. Apple's design treats
peripheral-side connection lifecycle as the central's responsibility;
the only tools the peripheral has are `removeAllServices()` and
`stopAdvertising()`, neither of which disconnects an existing link.

The current implementation hides this limitation behind a successful
return value, masking platform behavior.

**Notes.** Three viable fix paths:

1. **Throw `UnsupportedOperationException('disconnectCentral', 'ios')`.**
   Honest. Caller catches and uses the lifecycle disconnect command
   instead (which is best-effort but at least signals intent).
2. **Add `Capabilities.canForceDisconnectRemoteCentral: false` for iOS**
   and have the cross-platform `Server.disconnectCentral` check the
   capability before delegating. The capability flag also belongs on
   Android (see I207) — neither platform genuinely supports it.
3. **Send the lifecycle disconnect command (0x00 to heartbeat char) via
   notify, then mark the client locally as gone.** Best-effort but at
   least communicates intent if the central is a Bluey client.

Recommended: combine (2) and (3) — capability flag plus a "soft
disconnect" cooperative protocol via the existing lifecycle channel.

**External references.**
- Apple `CBPeripheralManager` documentation
  (no force-disconnect method exists):
  https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager
- Apple Developer Forums discussion (multiple threads, e.g.
  https://developer.apple.com/forums/thread/93060) confirming the
  platform limitation.
- Existing entry I207 (Android equivalent, marked wontfix) —
  consider whether I045 should also be wontfix or if the cooperative
  fallback is worth implementing.

---

### I046 — iOS `getMaximumWriteLength` implemented but not exposed via Pigeon

```yaml
---
id: I046
title: iOS `getMaximumWriteLength` implemented but not exposed via Pigeon
category: unimplemented
severity: medium
platform: ios
status: open
last_verified: 2026-04-26
related: [I034]
---
```

**Confidence: high.** Reviewer found the iOS impl but no Pigeon
declaration nor Dart-side wrapper.

**Symptom.** A consumer that wants to chunk a large value at the
optimal size for the negotiated MTU has no way to query
`peripheral.maximumWriteValueLength(for: writeType)`. The information
exists on iOS but isn't crossed over the FFI boundary.

**Location.**
- iOS implementation present:
  `bluey_ios/ios/Classes/CentralManagerImpl.swift:401`.
- Pigeon schema missing the method:
  `bluey_ios/pigeons/messages.dart` — no `getMaximumWriteLength` declaration.
- Platform interface lacks the abstract method:
  `bluey_platform_interface/lib/src/platform_interface.dart`.

**Root cause.** The iOS-side Swift function exists from earlier
implementation work, but the corresponding Pigeon HostApi method,
Dart-side wrapper in `IosConnectionManager`, and `BlueyPlatform`
abstract method were never added. The Swift function is dead code as
shipped.

**Notes.** Companion to I034 (Android side has the same gap). Fix
should be coherent across both platforms:

1. Add `getMaximumWriteLength(deviceId, withResponse) -> int` to
   `BlueyPlatform`.
2. Declare it in both `pigeons/messages.dart` files.
3. Implement Android side via `BluetoothGatt` (Android exposes this
   indirectly — derive from `mtu - 3` for write-with-response, or
   `min(mtu - 3, 512)` for write-without-response chunked, or query
   `BluetoothGatt`'s internal state).
4. Wire iOS through to the existing `peripheral.maximumWriteValueLength`.
5. Surface on `Connection` as `maximumWriteValueLength({withResponse: true})`.

**External references.**
- Apple `CBPeripheral.maximumWriteValueLength(for:)`:
  https://developer.apple.com/documentation/corebluetooth/cbperipheral/maximumwritevaluelength(for:)
- Punch Through "BLE Write Requests vs. Write Commands":
  https://punchthrough.com/ble-write-requests-vs-write-commands/
  (discusses the relationship between MTU and write-type-specific limits)

---

### I047 — iOS `pendingWriteRequests` batch responds only to first request

```yaml
---
id: I047
title: iOS `respondToWriteRequest` only responds to first of batched ATT requests
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-04-26
related: [I050]
---
```

**Confidence: low — needs investigation.** Reviewer read the code but
did not trace through a long-write flow with logs. The interpretation
is plausible but unverified.

**Symptom (suspected).** When a central performs a long write (BLE
prepare-write/execute-write flow) against a hosted characteristic on
iOS, the server may receive multiple `CBATTRequest` objects representing
the parts of the long write. The plugin stores these as a list under
a single Dart-visible `requestId`. When Dart calls `respondToWriteRequest`,
only `requests.first` receives a response from the OS. The remaining
parts (if iOS pre-staged them) are silently dropped.

The net effect — if the hypothesis is correct — is that long writes
to hosted iOS services either time out at the ATT layer or complete
successfully if the central is permissive about partial responses.

**Location.** `bluey_ios/ios/Classes/PeripheralManagerImpl.swift:165-172`.

```swift
guard let requests = pendingWriteRequests.removeValue(forKey: requestId), let firstRequest = requests.first else {
    completion(.failure(BlueyError.notFound.toServerPigeonError()))
    return
}
peripheralManager.respond(to: firstRequest, withResult: status.toCBATTError())
```

The data structure (`[Int: [CBATTRequest]]`) clearly anticipates multiple
requests per requestId — but the response loop is missing.

**Root cause (suspected).** Either the batching code was added in
anticipation of long-write support without completing the response
side, or iOS's actual long-write semantics (which the reviewer did
not verify against current iOS behavior) are different from what
the data structure implies.

**Verification steps for the CLI session.**

1. Find where `pendingWriteRequests[requestId]` is **populated** —
   look in `PeripheralManagerDelegate.swift` for the
   `peripheralManager(_:didReceiveWrite:requests:)` delegate method.
   Check if it ever appends multiple requests under one ID, or only
   ever a single-element array.
2. If only single-element arrays are ever stored, this finding is
   moot — close as wontfix or invalid.
3. If multi-element arrays are stored, write a unit test that
   simulates a long write (>MTU bytes) from a real central and
   observe what happens. Use an iOS device-to-device test or
   `nRF Connect` configured for a long write to confirm.

**Notes.** This finding is bundled with I050 (prepared-write flow
unimplemented) which already exists in the backlog as a known gap on
the **central** side. I047 would be the corresponding **server-side**
gap for the same protocol. Either close I047 if the server-side path
isn't actually broken, or fold into I050 as a coherent long-write
support spec.

**External references.**
- BLE Core Specification 5.4, Vol 3, Part F, §3.4.6: Prepare Write
  Request, Execute Write Request, Prepare Write Response.
- Apple `CBPeripheralManager.respond(to:withResult:)`:
  https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/respond(to:withresult:)
  — note the doc says: "The peripheral manager uses the first ATT
  request in the array to respond. You need to call this method in
  response to receiving a delegate method..."  — this suggests
  responding to the first request *is* the API contract for batched
  writes. **This may invalidate the finding entirely** — verify before
  taking action.

---

### I048 — iOS `CBManagerOptionRestoreIdentifierKey` not set; no state restoration

```yaml
---
id: I048
title: iOS managers initialized without restore identifier; state restoration disabled
category: limitation
severity: medium
platform: ios
status: open
last_verified: 2026-04-26
---
```

**Confidence: high.** Reviewer found `CBCentralManager(delegate: nil, queue: nil)`
and `CBPeripheralManager(delegate: nil, queue: nil)` at init — no options
dictionary passed.

**Symptom.** When the iOS app is force-killed (by the user or by iOS
itself under memory pressure) while serving as a peripheral or holding
central connections, the app cannot be relaunched in the background to
process subsequent BLE events. The `CBCentralManager` and
`CBPeripheralManager` instances are not registered with iOS's state
preservation system, so the OS doesn't track them across launches.

For consumers building apps that need long-running BLE in the background
(continuous monitoring, beacon-style proximity, multi-day connections),
this is a hard ceiling: the connection lifecycle ends when the app process
ends, regardless of `UIBackgroundModes` declarations.

**Location.**
- `bluey_ios/ios/Classes/CentralManagerImpl.swift:57` —
  `centralManager = CBCentralManager(delegate: nil, queue: nil)`
- `bluey_ios/ios/Classes/PeripheralManagerImpl.swift:37` —
  `peripheralManager = CBPeripheralManager(delegate: nil, queue: nil)`

**Root cause.** `CBManagerOptionRestoreIdentifierKey` is the iOS API
for opting in to state preservation/restoration. Without it, the
managers are created fresh on each launch and have no relationship to
any prior session.

Setting the restore identifier alone is not sufficient — the host
app's `AppDelegate` must also implement
`application(_:didFinishLaunchingWithOptions:)` to **synchronously**
re-instantiate the manager with the same identifier before the Flutter
engine plugin registrant runs, and the plugin's
`centralManager(_:willRestoreState:)` delegate method must reattach
delegates and re-acquire peripherals from the restored-state dictionary.

**Notes.** Implementation requires Flutter-plugin-level changes that
touch the host app's `AppDelegate` and Info.plist. Mirror what
`flutter_blue_plus` does:

- Plugin-level: accept a configuration option `restoreState: bool` and
  a `restoreIdentifier: String?` (default-derived).
- Host app: declare `bluetooth-central` and/or `bluetooth-peripheral`
  in `UIBackgroundModes`, and in `AppDelegate.swift` ensure the manager
  is re-instantiated synchronously in `application(_:didFinishLaunchingWithOptions:)`
  *before* `GeneratedPluginRegistrant.register(with:)`.
- Implement `centralManager(_:willRestoreState:)` and
  `peripheralManager(_:willRestoreState:)` to reattach delegates and
  rebuild the `peripherals: [String: CBPeripheral]` dict from
  `CBCentralManagerRestoredStatePeripheralsKey`.

This is non-trivial but it is the difference between "iOS background
BLE works" and "iOS background BLE works only as long as the user
doesn't force-quit the app."

**Force-quit caveat:** state restoration does NOT survive user-initiated
force-quit (swipe up in app switcher). This is by Apple design.
Document this loudly in the final integration guide.

**External references.**
- Apple "Performing Long-Term Actions in the Background":
  https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetoothLE/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
- Apple `CBCentralManagerOptionRestoreIdentifierKey`:
  https://developer.apple.com/documentation/corebluetooth/cbcentralmanageroptionrestoreidentifierkey
- Apple `centralManager(_:willRestoreState:)`:
  https://developer.apple.com/documentation/corebluetooth/cbcentralmanagerdelegate/centralmanager(_:willrestorestate:)
- `flutter_blue_plus` reference implementation
  (search their repo for `restoreState` and the Info.plist key
  `flutter_blue_plus_restore_state`):
  https://github.com/chipweinberger/flutter_blue_plus

---

### I054 — Dead event types in `events.dart`

```yaml
---
id: I054
title: Several `BlueyEvent` subtypes are defined but never emitted
category: no-op
severity: low
platform: domain
status: open
last_verified: 2026-04-26
---
```

**Confidence: high.** Reviewer grepped `_emitEvent` and `_eventBus.emit`
across `bluey/lib/src/`; no emissions of these types found.

**Symptom.** Consumers subscribing to `bluey.events` expect to see
GATT-operation events (read, write, notify, service discovery) based on
the catalog in `events.dart`. They never arrive. The `Bluey` instance
emits only scan, connect, server, advertising, and error events.

**Location.** `bluey/lib/src/events.dart` defines the following types
that are never `emit()`ed anywhere in the production codebase:

- `DiscoveringServicesEvent` (line 124)
- `ServicesDiscoveredEvent` (line 135)
- `CharacteristicReadEvent` (line 151)
- `CharacteristicWrittenEvent` (line 169)
- `NotificationReceivedEvent` (line 191)
- `NotificationSubscriptionEvent` (line 209)
- `DebugEvent` (line 418)

The structured logging in `_loggedGattOp` at
`bluey/lib/src/connection/bluey_connection.dart:80-112` produces
equivalent information via `dev.log` but does not also emit events.

**Root cause.** Implementation gap. The event types were declared as
part of the catalog but the emission sites were never added to
`_loggedGattOp` or `BlueyRemoteCharacteristic`/`BlueyRemoteDescriptor`.

**Notes.** Two viable resolutions:

1. **Emit from `_loggedGattOp` success paths.** Add a `event:` callback
   parameter to `_loggedGattOp` that constructs the appropriate event
   given the operation name and result, then call it on success.
   Hook this into every call site — `BlueyRemoteCharacteristic.read`/
   `write`, `BlueyConnection.services`, `BlueyRemoteCharacteristic.notifications`.

2. **Delete the dead types.** If the events stream is intended only for
   high-level lifecycle (connect/scan/server), document that and remove
   the GATT-op event types.

Recommended: option (1). The events stream is the right diagnostic API
for consumer-visible monitoring; the structured `dev.log` calls give
essentially the same data but are harder to consume programmatically.

**External references.** None applicable; this is a purely internal
implementation gap.

---

### I055 — `PeerDiscovery` doesn't filter scan by control-service UUID

```yaml
---
id: I055
title: PeerDiscovery scans without service filter; probes every nearby device
category: limitation
severity: medium
platform: domain
status: open
last_verified: 2026-04-26
related: [I056, I057]
---
```

**Confidence: high.**

**Symptom.** `bluey.discoverPeers()` and `BlueyPeer.connect()` both
delegate to `PeerDiscovery._collectCandidates`, which scans with an
empty `serviceUuids` list. Every BLE device in range becomes a
candidate. Each candidate is then connect-probed sequentially in
`_probeServerId`/`_readServerIdRaw` to read the serverId characteristic.

In a typical environment with 10-30 nearby BLE devices (offices,
homes with smart-home gear, public spaces), peer discovery takes
20-60 seconds because the probe is O(n) sequential connect-disconnect
cycles at ~1-2 seconds each.

**Location.** `bluey/lib/src/peer/peer_discovery.dart:85-99`.

```dart
final scanConfig = platform.PlatformScanConfig(
  serviceUuids: const [],   // <- empty filter
  timeoutMs: timeout.inMilliseconds,
);
```

**Root cause.** The Bluey server eagerly adds the control service
(`b1e70001-0000-1000-8000-00805f9b34fb`) but does not advertise it.
Even if it did advertise it, the discovery scan filter doesn't pass it
through, so the OS-level scan doesn't filter on it.

**Notes.** The control service UUID is the natural filter for peer
discovery — it uniquely identifies a Bluey-protocol peer.

Two-part fix:

1. **Server side:** include the control service UUID in the advertising
   payload by default. This consumes 18 bytes (16 UUID + 2 header)
   from the 31-byte legacy advertising budget — non-trivial. On iOS,
   the OS automatically promotes 128-bit UUIDs to the overflow area
   when scanning is foreground, so it remains discoverable to other
   Bluey clients explicitly scanning for that UUID. On Android, it
   appears in the primary advertisement.
2. **Client side:** change `_collectCandidates` to filter by the
   control service UUID:

```dart
final scanConfig = platform.PlatformScanConfig(
  serviceUuids: [lifecycle.controlServiceUuid],
  timeoutMs: timeout.inMilliseconds,
);
```

Probe time becomes O(matches) rather than O(nearby devices).

**Privacy tradeoff.** Advertising the control service UUID exposes a
stable Bluey-using-app fingerprint. For privacy-sensitive deployments
(consumer apps where users don't want their app stack identifiable
from a passive BLE scan), this is undesirable. Make the advertising
of the control UUID a configurable option on `Server.startAdvertising`.

**External references.**
- BLE Core Specification 5.4, Vol 3, Part C, §11: GAP modes and
  advertising data formats.
- Apple "Advertising and Discoverability":
  https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetoothLE/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
  (overflow area discussion)

---

### I056 — `PeerDiscovery` probe-connect has no timeout

```yaml
---
id: I056
title: PeerDiscovery probe-connect uses platform default timeout (Android 30s, iOS infinite)
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-26
related: [I055]
---
```

**Confidence: high.**

**Symptom.** During peer discovery, if any candidate device is
unresponsive (BLE devices in deep-sleep state often are on first
connect attempt), the probe's connect call waits for the platform's
default timeout — ~30 seconds on Android (or ~10 seconds on Samsung),
indefinitely on iOS. A single unresponsive candidate blocks all
subsequent probes for the duration of its timeout.

For a discovery session with `scanTimeout: 5 seconds` and 10
candidates, one stuck candidate can stretch total discovery time to
35+ seconds — 7× the user-visible expected duration.

**Location.** `bluey/lib/src/peer/peer_discovery.dart:115-120`.

```dart
Future<ServerId> _readServerIdRaw(String address) async {
  final config = const platform.PlatformConnectConfig(
    timeoutMs: null,        // <- relies on platform default
    mtu: null,
  );
  await _platform.connect(address, config);
  ...
}
```

**Root cause.** The `timeoutMs: null` path defers to the platform's
default. The default differs per platform and is unsuitable for
throw-away probes.

**Notes.** Pass an explicit short timeout (3 seconds is a reasonable
default for a probe; the device either responds quickly or gets skipped).

```dart
final config = const platform.PlatformConnectConfig(
  timeoutMs: 3000,
  mtu: null,
);
```

If the connect throws `GattOperationTimeoutException` after 3 seconds,
the probe loop already catches and skips. No further changes needed.

Consider exposing this as a parameter on `Bluey.discoverPeers` for
power users who want to tune it.

**External references.**
- Bluey divergence reference, Section 1.3 (connect timeouts) and
  Section 1.4 (in-flight operation behavior on disconnect).

---

### I057 — MAC-to-UUID coercion duplicated in two places

```yaml
---
id: I057
title: `_addressToUuid` / `_deviceIdToUuid` are duplicated and both wrong
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-04-26
related: [I006]
---
```

**Confidence: high.**

**Symptom.** Same code (truncate-and-pad MAC to UUID format) exists
in two places, and both are broken in the same way (I006 documents the
brokenness). Fixing one without the other leaves the bug in place.

**Location.**
- `bluey/lib/src/bluey.dart:587-598` — `_deviceIdToUuid`.
- `bluey/lib/src/peer/peer_discovery.dart:130-137` — `_addressToUuid`.

The two functions are byte-identical except for variable names.

**Root cause.** Copy-paste during the peer module addition. The
underlying issue is that `Device.id` (a `UUID`) and `device.address`
(the platform's native identifier) are conflated — synthesizing a
fake UUID from a MAC is a workaround, not a model.

**Notes.** Fixing this properly is bound up with I006's resolution
(introduce a typed `DeviceIdentifier` value object that distinguishes
`MacAddress`, `IosUuid`, and `BlueyServerId` variants). In the interim,
extract the coercion into a single utility function in
`bluey/lib/src/shared/` and have both call sites delegate.

Since I006 captures the underlying issue, this entry exists to flag
the duplication to whoever fixes I006. Consider closing I057 with
`status: subsumed-by` once the proper fix lands.

**External references.**
- Existing entry I006 — primary diagnosis.

---

### I058 — `BlueyServer.startAdvertising` drops user's `mode` parameter

```yaml
---
id: I058
title: BlueyServer.startAdvertising drops user-supplied advertising mode
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-26
related: [I051]
---
```

**Confidence: high.** Reviewer confirmed by reading both the call site
and the constructor signature.

**Symptom.** A consumer calling `server.startAdvertising(mode: AdvertiseMode.lowPower)`
sees no effect on Android — the advertising interval remains the
default. The `mode` parameter is silently dropped between Dart and
the platform.

**Location.** `bluey/lib/src/gatt_server/bluey_server.dart:173-179`.

```dart
final config = platform.PlatformAdvertiseConfig(
  name: name,
  serviceUuids: services?.map((u) => u.toString()).toList() ?? [],
  manufacturerDataCompanyId: manufacturerData?.companyId,
  manufacturerData: manufacturerData?.data,
  timeoutMs: timeout?.inMilliseconds,
  // mode: ???   <- not passed
);
```

The `Server.startAdvertising` interface doesn't expose `mode` at all
— so the issue is twofold: (a) the public API doesn't have the
parameter, and (b) even if added, the platform-config builder would
need updating.

**Root cause.** Implementation oversight. The platform interface
already supports it (`PlatformAdvertiseConfig.mode`), the Pigeon DTOs
support it (`AdvertiseConfigDto.mode` with `AdvertiseModeDto` enum),
the Android side honors it — but the Dart-side public Server interface
and `BlueyServer.startAdvertising` don't propagate it.

**Notes.** Two-step fix:

1. Add `AdvertiseMode` enum to the public domain layer
   (`bluey/lib/src/gatt_server/server.dart` or similar).
2. Add `mode` parameter to `Server.startAdvertising`, default to
   `balanced`, propagate to `PlatformAdvertiseConfig.mode` in
   `BlueyServer`.

Document loudly that `mode` is Android-only — iOS manages advertising
intervals automatically.

This is a subset of I051 (advertising options not exposed) but
specifically the `mode` parameter has all the plumbing in place; only
the final hop is missing.

**External references.**
- Android `AdvertiseSettings.Builder.setAdvertiseMode(int)`:
  https://developer.android.com/reference/android/bluetooth/le/AdvertiseSettings.Builder#setAdvertiseMode(int)

---

### I059 — `BlueyServer.removeService` is fire-and-forget (unawaited)

```yaml
---
id: I059
title: BlueyServer.removeService doesn't await the platform call
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-04-26
related: [I086]
---
```

**Confidence: high.**

**Symptom.** A consumer calling `server.removeService(uuid)` returns
synchronously (the method is declared `void`, not `Future<void>`),
giving no signal of when the underlying platform call has completed
or whether it failed. Errors from the platform-side removal are
silently swallowed.

**Location.** `bluey/lib/src/gatt_server/bluey_server.dart:158-160`.

```dart
@override
void removeService(UUID uuid) {
  _platform.removeService(uuid.toString());
}
```

The platform method returns `Future<void>` but the call site doesn't
await it; the wrapper method's return type (`void`) makes it
impossible for callers to await either.

**Root cause.** API shape mismatch. The Server interface declared
`removeService` as synchronous, but the underlying operation is
asynchronous and can fail.

**Notes.** Change `Server.removeService` to return `Future<void>`,
await the platform call, propagate errors. This is a breaking API
change; account for it in the next minor version.

This issue compounds with I086 (`removeService` races with in-flight
notify fanout): with a fire-and-forget removal, the consumer cannot
even sequence "stop fanning notifies before removing" without race
windows.

**External references.**
- Existing entry I086 — race condition between removeService and notify.

---

### I065 — `Capabilities` matrix doesn't gate any production code path

```yaml
---
id: I065
title: Capabilities matrix is decorative; no production code consults it
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-26
related: [I053, I035, I066]
---
```

**Confidence: high.** Reviewer grepped for `_capabilities`,
`capabilities.can`, etc. — only one production check found.

**Symptom.** The `Capabilities` value object exists on `Bluey.capabilities`
and on the platform interface. It documents what the platform supports.
But almost no production code reads it before calling a feature.
A consumer call to `connection.requestPhy(...)` on iOS does not check
`capabilities.canRequestPhy` — it just calls through and silently
no-ops or throws an obscure error.

The single existing check is `Bluey.server()` returning null when
`!capabilities.canAdvertise`. That's it.

**Location.** Confirmed via grep across `bluey/lib/src/`:
- `bluey/lib/src/bluey.dart:501` — only production capability check.

The matrix declaration is at:
- `bluey_platform_interface/lib/src/capabilities.dart`.

**Root cause.** Capability flags were modeled and populated, but the
discipline of "check capability before delegating to platform" was not
established as a coding standard. New methods get added without
adding their corresponding capability flag or check.

**Notes.** Three-part fix:

1. **Expand the matrix** to cover every real asymmetry. Currently
   8 flags; should be ~25 (see I053). Suggested additions:
   - `canRequestPhy: bool`
   - `canRequestConnectionParameters: bool`
   - `canRequestConnectionPriority: bool`
   - `canForceDisconnectRemoteCentral: bool`
   - `canRefreshGattCache: bool`
   - `canAdvertiseManufacturerData: bool`
   - `canAdvertiseInBackgroundWithName: bool`
   - `canFilterScanByName: bool`
   - `canFilterScanByManufacturerData: bool`
   - `canRetainPeripheralAcrossReinstall: bool`
   - `canDoExtendedAdvertising: bool`
   - `canDoCodedPhy: bool`
   - `canL2capCoc: bool`
   - `canStateRestoration: bool`

2. **Establish a capability-gating helper** in domain code:

   ```dart
   T _requireCapability<T>(bool flag, String op, T Function() body) {
     if (!flag) throw UnsupportedOperationException(op, _platformName());
     return body();
   }
   ```

3. **Consult capability flags from every cross-platform method** that
   might not be supported. `Connection.requestPhy`, `bond`, etc. should
   wrap their delegation in `_requireCapability`. (See also I066, which
   recommends the more invasive structural fix of moving these methods
   off `Connection` entirely.)

Without (3), the matrix is documentation only. With (3), the matrix
becomes load-bearing and consumers can rely on it.

**External references.**
- Existing entry I053 (capabilities matrix incomplete) — partial overlap;
  may consolidate with I065.

---

### I066 — `Connection` interface exposes platform-specific methods cross-platform (architectural)

```yaml
---
id: I066
title: Cross-platform Connection interface declares platform-specific methods
category: bug
severity: high
platform: domain
status: open
last_verified: 2026-04-26
related: [I030, I031, I032, I035, I045, I065, I200]
---
```

**Confidence: high.** This is the architectural framing of an issue
already partly captured by individual stub entries.

**Symptom.** The `Connection` abstract interface declares
`bond()`, `removeBond()`, `bondState`, `bondStateChanges`,
`requestPhy()`, `txPhy`, `rxPhy`, `phyChanges`,
`requestConnectionParameters()`, `connectionParameters` as if they
were portable cross-platform methods. They aren't — Android stubs
(I035) are silent successes; iOS doesn't expose these APIs at all
(I200 documents the Apple limitation as wontfix).

The result is an API that lies about what the library can do. There
is no compile-time signal of platform asymmetry. There is no runtime
capability check (see I065). Calls succeed and return fake data, or
throw obscure errors, depending on platform.

**Location.** `bluey/lib/src/connection/connection.dart:205-287`.

The "Bonding", "PHY", and "Connection Parameters" sections (line
comments at 205, 237, 269) declare ten methods/getters/streams that
are platform-asymmetric.

**Root cause.** The interface was modeled after the union of features
across platforms rather than the intersection (cross-platform) plus
platform-specific extensions. This is the structural inverse of the
right shape for a cross-platform abstraction.

**Notes.** This is the architectural rewrite that resolves I030/I031/I032/
I035/I045/I200 in one structurally-sound move.

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

  // Android-specific connection priority (separate from full connection params)
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

The type system now mirrors reality. Code that needs bonding has to
explicitly opt into Android-only, which surfaces the asymmetry at
review time.

This is a breaking change. Plan it as a major version bump, with a
migration guide.

**Verification & validation.** The CLI session should:

1. Confirm reviewer's read of the `Connection` interface is correct
   (re-read `bluey/lib/src/connection/connection.dart`).
2. Confirm that Android `bond()` etc. are stubs (cross-reference I035).
3. Confirm that iOS `bond()` etc. are unsupported by reading
   `bluey_ios/lib/src/ios_connection_manager.dart`.
4. Decide whether the proposed shape is acceptable; this is a major
   API decision that may want broader discussion before being
   committed to as a backlog item.

**External references.**
- Effective Dart "Avoid defining unnecessary getters and setters":
  https://dart.dev/effective-dart/design#avoid-defining-unnecessary-getters-and-setters
- Apple Accessory Design Guidelines, R8 (BLE):
  https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf
  — confirms iOS does not expose central-side bond/PHY/conn-param control.
- `flutter_blue_plus` uses Boolean capability flags rather than typed
  extensions; it does not solve this problem cleanly. The proposed shape
  is novel within the Flutter BLE ecosystem.

---

### I067 — Two-state `ConnectionState` lacks "linked vs ready" distinction

```yaml
---
id: I067
title: ConnectionState collapses link-up and services-discovered into one state
category: limitation
severity: medium
platform: domain
status: open
last_verified: 2026-04-26
---
```

**Confidence: medium.** The reviewer believes the conflation is real
but the practical impact depends on whether consumers ever observe
`state == connected` while services are not yet discovered. In the
current code, `Bluey.connect()` runs services discovery before
returning the Connection, so the conflation may be hidden.

**Symptom.** The `ConnectionState` enum has four values
(`disconnected`, `connecting`, `connected`, `disconnecting`). There
is no value that distinguishes "link established but services not
yet discovered" from "fully ready for GATT operations." A consumer
that subscribes to `connection.stateChanges` and reacts to `connected`
by issuing reads/writes might do so before service discovery
completes, depending on how the Connection was obtained.

**Location.** `bluey/lib/src/connection/connection_state.dart:1-13`.

**Root cause.** The state machine mirrors the OS's link-layer view
(disconnected/connecting/connected/disconnecting) rather than the
domain-meaningful "ready for GATT ops" view. BLE connections have
multiple post-link initialization steps (services discovery, optional
MTU negotiation, optional CCCD subscriptions, optional bond) before
they are usable.

In the current Bluey code, `Bluey.connect()` and `BlueyPeer.connect()`
both run services discovery internally before returning, so the
"linked but not ready" window is never observable from the public
Connection. But the state machine itself doesn't enforce this — a
future code path that returns the Connection earlier would expose the
gap.

**Notes.** The cleanest fix is a tri-state lifecycle:

```dart
enum ConnectionState {
  disconnected,
  connecting,
  linked,           // link established; services not yet discovered
  ready,            // services discovered; usable for GATT ops
  disconnecting;
}
```

`Bluey.connect()` continues to await `ready` before returning the
Connection. Consumers that subscribe to `stateChanges` see the explicit
`linked → ready` transition.

This is a domain modeling improvement that supports future use cases
(e.g., exposing partial connections for diagnostic UIs).

**Verification.** The CLI should check whether any current code path
returns a Connection in `connected` state without having discovered
services. If none exists, this is a forward-looking architectural
concern, not a current bug — adjust severity to `low`.

**External references.**
- Bluey divergence reference, Section 2.8 ("Connected but services
  not discovered phase").
- Nordic recommendation to delay 600-1600ms after `STATE_CONNECTED`
  before calling `discoverServices()` for bonded devices:
  https://devzone.nordicsemi.com/f/nordic-q-a/4608/gatt-characteristic-read-timeout

---

### I068 — `BlueyEventBus` missing lifecycle/heartbeat events

```yaml
---
id: I068
title: Lifecycle protocol state changes not emitted as BlueyEvents
category: no-op
severity: low
platform: domain
status: open
last_verified: 2026-04-26
related: [I054]
---
```

**Confidence: high.**

**Symptom.** Consumers monitoring `bluey.events` cannot observe
heartbeat-protocol behavior: heartbeat sent, heartbeat acknowledged,
heartbeat failed (transient vs counted), threshold tripped (server
declared unreachable), pending-request pause, server-side client-gone
detection. These are visible only via `dev.log` strings.

For a library whose distinguishing feature is its lifecycle protocol,
the protocol's own state transitions are the highest-value diagnostic
events.

**Location.**
- `bluey/lib/src/connection/lifecycle_client.dart` — fires `dev.log`
  at lines 116, 193, 266, 272 for various heartbeat events.
- `bluey/lib/src/gatt_server/lifecycle_server.dart` — no diagnostic
  events at all.

**Root cause.** Lifecycle classes don't have `BlueyEventBus` injected.
Adding events would require threading the bus through `LifecycleClient`
and `LifecycleServer` constructors.

**Notes.** Suggested events to add to `events.dart`:

- `HeartbeatSentEvent(deviceId)`
- `HeartbeatAcknowledgedEvent(deviceId)`
- `HeartbeatFailedEvent(deviceId, consecutive, isDeadPeerSignal)`
- `PeerDeclaredUnreachableEvent(deviceId, threshold)`
- `LifecyclePausedForPendingRequestEvent(clientId)`  (server-side)
- `ClientLifecycleTimeoutEvent(clientId)` (server-side)

Threading: pass `BlueyEventBus` into `LifecycleClient` and `LifecycleServer`
constructors. Update the `Connection`-side construction in
`Bluey.connect`/`BlueyPeer.connect` to thread the bus through.

Pair this with I054 (dead GATT-op event types) — both are about
making the events stream as comprehensive as the catalog suggests.

**External references.** None applicable; this is a purely internal
implementation gap.

---

### I069 — `FakeBlueyPlatform.capabilities` hardcoded; tests don't exercise capability gating

```yaml
---
id: I069
title: FakeBlueyPlatform.capabilities is hardcoded; no test coverage of capability-based branching
category: limitation
severity: medium
platform: domain
status: open
last_verified: 2026-04-26
related: [I065, I066]
---
```

**Confidence: high.**

**Symptom.** `FakeBlueyPlatform` declares `_capabilities` as a `final`
field with hardcoded values
(`canScan: true, canConnect: true, canAdvertise: true`). Tests cannot
swap in iOS-style capabilities (`canBond: false`, `canRequestPhy: false`,
etc.) to exercise the capability-gated code paths.

Combined with I065 (no production code consults capabilities), this
means the test suite has zero coverage of "what does my code do when
a feature isn't supported on this platform?" The only such case is
implicit (I035 silent stubs), which silently passes tests.

**Location.** `bluey/test/fakes/fake_platform.dart:35-39`.

**Root cause.** The fake was designed before capability gating was
added as an architectural concern. It models the union of features
(everything supported), not the intersection.

**Notes.** Refactor the fake to accept a `Capabilities` in its
constructor:

```dart
final class FakeBlueyPlatform extends BlueyPlatform {
  FakeBlueyPlatform({Capabilities? capabilities})
      : _capabilities = capabilities ?? const Capabilities(
          canScan: true,
          canConnect: true,
          canAdvertise: true,
        ),
        super.impl();
  final Capabilities _capabilities;
  @override
  Capabilities get capabilities => _capabilities;
  // ...
}
```

Tests can then construct platform-restricted fakes:

```dart
final iosLikePlatform = FakeBlueyPlatform(
  capabilities: Capabilities.iOS,  // bond=false, etc.
);
```

Once available, add tests that exercise expected `UnsupportedOperationException`
behavior for each capability-gated method. This is the test-side
counterpart of I065's "make capabilities load-bearing" goal.

**External references.** None applicable.

---

## ARCHITECTURAL REWRITES — to verify and create as backlog entries

These are the four "rewrite" recommendations from the review. Per
project convention, they are filed as backlog entries here so that
the `superpowers` skill can later expand each into a full plan/spec
under `docs/superpowers/specs/`.

### I088 — Rewrite Pigeon GATT schema to carry service/characteristic context

```yaml
---
id: I088
title: Rewrite Pigeon GATT schema to thread service/characteristic context through every call
category: bug
severity: critical
platform: platform-interface
status: open
last_verified: 2026-04-26
related: [I010, I011, I016]
---
```

**Confidence: high.**

**Symptom.** I010, I011, and I016 all stem from the same root cause:
the Pigeon schema for GATT operations carries only
`(deviceId, characteristicUuid)` or `(deviceId, descriptorUuid)` tuples,
not the full identity context. On peripherals with multiple services
exposing characteristics with the same UUID, or multiple notifiable
characteristics (each carrying a CCCD `0x2902`), operations are
non-deterministically routed to the wrong attribute.

This is a wire-protocol-level identity-loss problem affecting every
GATT operation. The current backlog tracks the consequences as separate
critical entries; this entry exists to track the coherent rewrite.

**Location.**
- `bluey_android/pigeons/messages.dart` — the schema declarations.
- `bluey_ios/pigeons/messages.dart` — same schema.
- `bluey_platform_interface/lib/src/platform_interface.dart` —
  abstract methods mirror the schema.
- All Android/iOS implementations — receivers of the calls.

**Root cause.** Initial schema design conflated UUID identity with
attribute identity. UUIDs are not unique within a peripheral's GATT
database; (service, characteristic, instance) is the unique identity.

**Notes.** Two viable schemas:

**Option A — explicit service/characteristic context tuples:**

```dart
// Pigeon schema additions:
@async
Uint8List readCharacteristic(
  String deviceId,
  String serviceUuid,
  String characteristicUuid,
);

@async
void writeDescriptor(
  String deviceId,
  String serviceUuid,
  String characteristicUuid,
  String descriptorUuid,
  Uint8List value,
);
```

Pros: simple, language-portable. Cons: can't disambiguate two
characteristics with the same UUID *within* the same service (rare
but spec-allowed).

**Option B — opaque platform handles (preferred for "perfection"):**

The platform side assigns an opaque integer or string handle to each
discovered attribute (e.g., Android's `BluetoothGattCharacteristic.getInstanceId()`).
The handle is returned in `discoverServices` results and used as the
key in subsequent ops. The Dart side never tries to identify
attributes by UUID alone — it carries handles.

```dart
// Pigeon schema with handle-based identity:
class CharacteristicDto {
  final String uuid;
  final int handle;     // <- opaque, platform-assigned
  // ...
}

@async
Uint8List readCharacteristic(String deviceId, int characteristicHandle);
```

Pros: spec-correct, robust to duplicate UUIDs at any level. Cons:
handles must be lifetime-managed (invalidated on Service Changed,
disconnect); requires platform-side handle table.

**Recommended path:** Option B. The reference implementation pattern
is `bluetooth_low_energy_android` (mentioned in I010 notes) which uses
`getInstanceId()`. This is the spec-faithful approach.

This rewrite is breaking. Plan as a major version bump, with a migration
guide.

**Spec hand-off.** This entry is intended to be expanded into a full
spec under `docs/superpowers/specs/` via the superpowers skill. Suggested
spec name: `2026-XX-XX-pigeon-gatt-handle-rewrite-design.md`.

**External references.**
- Android `BluetoothGattCharacteristic.getInstanceId()`:
  https://developer.android.com/reference/android/bluetooth/BluetoothGattCharacteristic#getInstanceId()
- BLE Core Specification 5.4, Vol 3, Part G, §3.2.2: characteristic
  declaration uniqueness within a service.
- `bluetooth_low_energy_android` reference impl:
  https://github.com/yanshouwang/bluetooth_low_energy
  (search for `instanceId` usage in their characteristic lookup).

---

### I089 — Rewrite `Connection` to remove platform-specific methods (architectural)

```yaml
---
id: I089
title: Rewrite Connection interface to use platform-tagged extensions for asymmetric features
category: bug
severity: high
platform: domain
status: open
last_verified: 2026-04-26
related: [I066, I030, I031, I032, I035, I045, I065, I200]
---
```

**Confidence: high.**

**Symptom.** Same as I066 — the cross-platform Connection interface
declares platform-asymmetric methods. This entry is the rewrite
counterpart, intended for superpowers-skill expansion.

**Notes.** See I066 for the proposed shape. The rewrite touches:

- `bluey/lib/src/connection/connection.dart` — interface.
- `bluey/lib/src/connection/bluey_connection.dart` — implementation;
  bond/PHY/conn-param logic moves to platform-tagged subclass or
  composition.
- All call sites in user code — breaking API change.

**Spec hand-off.** Suggested spec name:
`2026-XX-XX-platform-tagged-connection-extensions-design.md`.

**External references.** See I066.

---

### I098 — Rewrite Android `ConnectionManager` threading + disconnect lifecycle

```yaml
---
id: I098
title: Coherent rewrite of Android ConnectionManager — threading invariants + disconnect lifecycle
category: bug
severity: high
platform: android
status: open
last_verified: 2026-04-26
related: [I060, I061, I062, I064]
---
```

**Confidence: high.**

**Symptom.** Three high-severity issues in `ConnectionManager.kt` are
correctly diagnosed as separate backlog entries (I060 fire-and-forget
disconnect, I061 cleanup orphans pending callbacks, I062 binder-thread
mutation), plus the dead-code cleanup (I064). All four share the same
file and overlapping fix logic. Fixing them piecemeal risks introducing
new races between fixes.

**Notes.** Bundle as a single coherent rewrite:

1. **Delete legacy `pending*` and `pending*Timeouts` maps (I064).**
   These have been dead since Phase 2a. The cleanup paths still
   reference them; remove the references too.
2. **Wrap every `when` branch body of `onConnectionStateChange` in
   `handler.post` (I062).** Use the pattern from I062's fix sketch
   verbatim. After this, all map mutations are on the main thread.
3. **Make `disconnect()` await `STATE_DISCONNECTED` (I060).** Replace
   the synchronous `callback(Result.success(Unit))` with a pending
   completer registered before `gatt.disconnect()`. The
   `STATE_DISCONNECTED` branch invokes the completer.
4. **Add a 5-second fallback timer (I060/I061).** If
   `STATE_DISCONNECTED` doesn't fire, force-call `gatt.close()` and
   complete the callback with a synthesized `gatt-disconnected` error.
5. **Add a `connect()` mutex** to prevent the race documented in the
   review (two simultaneous connects to the same device).

The result is a single ~2-day PR that resolves four backlog entries
and significantly reduces flakes under stress testing.

**Verification.** Once implemented, validate against the existing
stress test suite (especially `runSoak` and `runFailureInjection`)
to confirm no regressions. Add a multi-connect race test as suggested
in I062's notes.

**Spec hand-off.** Suggested spec name:
`2026-XX-XX-android-connection-manager-rewrite-design.md`.

**External references.**
- Existing entries I060, I061, I062, I064 — primary diagnoses.
- Punch Through "Android BLE: The Ultimate Guide to Bluetooth Low Energy":
  https://punchthrough.com/android-ble-guide/
- Martijn van Welie "Making Android BLE Work — Part 2":
  https://medium.com/@martijn.van.welie/making-android-ble-work-part-2-47a3cdaade07
- AOSP `gatt_api.h`:
  https://android.googlesource.com/platform/external/bluetooth/bluedroid/+/master/stack/include/gatt_api.h

---

### I099 — Rewrite `Bluey._wrapError` and peer-error-wrapping to typed catch ladder

```yaml
---
id: I099
title: Replace string-matching error wrapping with typed catch ladder throughout domain layer
category: bug
severity: high
platform: domain
status: open
last_verified: 2026-04-26
related: [I090, I092]
---
```

**Confidence: high.**

**Symptom.** `Bluey._wrapError` uses `error.toString().toLowerCase().contains(...)`
to classify errors into domain exceptions. This is brittle (locale-sensitive,
format-sensitive, dependent on every platform's error string), and it
discards the typed exceptions that the platform interface already
produces (`GattOperationTimeoutException`, etc.). The right path
through `_runGattOp` exists for GATT operations, but `connect`,
`disconnect`, `bond`, `removeBond`, `requestPhy`,
`requestConnectionParameters`, `requestEnable`, `authorize`,
`openSettings`, `bondedDevices`, `configure` all bypass it.

**Location.**
- `bluey/lib/src/bluey.dart:605-642` — `_wrapError`.
- `bluey/lib/src/bluey.dart:223-275` — methods that call `_wrapError`
  instead of typed translation.
- `bluey/lib/src/connection/bluey_connection.dart:381-467` —
  `disconnect`, `bond`, `removeBond`, `requestPhy`,
  `requestConnectionParameters` bypass `_runGattOp`.

**Root cause.** Two error-translation paths emerged: a typed catch
ladder (`_runGattOp`) for GATT operations, and a string-matching
fallback (`_wrapError`) for everything else. The string-matching
path predates the typed platform-interface exception hierarchy and
was never retired.

**Notes.** Coherent fix:

1. **Extract the `_runGattOp` catch ladder into a shared helper**
   in `bluey/lib/src/shared/error_translation.dart` or similar.
   Make it operation-agnostic; `_runGattOp` becomes a thin wrapper
   that adds the activity-recording side effect.

2. **Replace every `_wrapError` call with the typed helper.**
   `_wrapError` is deleted; the `_errorController.add(...)` side
   effect is inlined where it's actually wanted (probably only at
   the top-level Bluey error stream, not at every operation).

3. **Extend `BlueyConnection.disconnect/bond/removeBond/requestPhy/
   requestConnectionParameters` to use the typed helper too.** This
   is I090 generalized.

4. **Add typed translation to `Scanner` operations (I092 currently
   open).** Same helper, same path.

5. **Preserve the lifecycle-accounting hook from the peer-silence
   branch.** Once the peer-silence branch merges, `_runGattOp` does
   typed exception translation *and* lifecycle accounting
   (`markUserOpStarted` / `markUserOpEnded` / `recordActivity` /
   `recordUserOpFailure`) through one funnel. Any extracted helper
   must thread an optional `LifecycleClient?` parameter through so
   the lifecycle accounting is preserved at every call site that
   uses it. The extraction shape is roughly:

   ```dart
   // In bluey/lib/src/shared/error_translation.dart:
   Future<T> translateGattErrors<T>(
     UUID deviceId,
     String operation,
     Future<T> Function() body, {
     LifecycleClient? lifecycleClient,  // <- preserved
   }) async {
     lifecycleClient?.markUserOpStarted();
     try {
       final result = await body();
       lifecycleClient?.recordActivity();
       return result;
     } on platform.GattOperationTimeoutException catch (e) {
       lifecycleClient?.recordUserOpFailure(e);
       throw GattTimeoutException(operation);
     }
     // ... rest of catch ladder ...
     finally {
       lifecycleClient?.markUserOpEnded();
     }
   }
   ```

   Call sites that don't have a lifecycle (e.g., `Bluey.requestEnable`,
   `Scanner.scan`) pass `lifecycleClient: null` and the accounting is
   skipped — only the exception translation runs. The single helper
   serves both populations.

6. **Maintain the `recordUserOpFailure` filter.** The peer-silence
   branch deliberately filters in `recordUserOpFailure` to only
   treat `GattOperationTimeoutException` as a peer-silence signal —
   user-op `statusFailed` errors (auth, write-not-permitted, etc.)
   are not peer-death signals. The rewrite must not break this
   distinction.

**Spec hand-off.** Suggested spec name:
`2026-XX-XX-typed-error-translation-rewrite-design.md`.

**External references.**
- Existing entries I090 (connect/disconnect bypass) and I092 (scan
  errors not translated).
- Effective Dart "Use exception types that are documented and
  enforce a sealed hierarchy":
  https://dart.dev/effective-dart/usage#avoid-catches-without-on-clauses

---

## UPDATES TO EXISTING ENTRIES

These are not new entries; they are notes to apply to existing entries
in HEAD.

### Update to I010 — Add iOS server-side mirror as additional location

**Current entry's Location:**
> `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:749-759`

**Add to Location:**
> Mirror on iOS server side: `bluey_ios/ios/Classes/PeripheralManagerImpl.swift:18, 53`
> — `characteristics: [String: CBMutableCharacteristic]` keyed by
> charUuid alone. Same dimensional error in the hosted-service
> bookkeeping. (See also I016.)

**Add to related:** `[I011, I016]`.

**Confidence: high.** The reviewer confirmed by direct read.

---

### Update to I040 — Refine root cause: backpressure misclassified as failure, not just "no retry"

**Current entry presumably says:** notification flow control isn't
implemented; failed notifications aren't retried via
`isReadyToUpdateSubscribers`.

**Refinement to add to Symptom or Root cause:**

> The current code's failure mode is *worse* than just "no retry."
> When `peripheralManager.updateValue(...)` returns `false`
> (which is iOS's documented backpressure signal — queue full,
> retry later), the Dart-side caller receives
> `BlueyError.unknown.toServerPigeonError()`, which surfaces as
> `BlueyPlatformException(code: 'bluey-unknown')`. The caller
> sees a generic error, has no signal that the data was simply
> queued behind backpressure, and may log/retry/double-send.
>
> The proper handling has two components:
> (a) accept the value into a Swift-side retry queue and
>     re-emit from `peripheralManagerIsReady(toUpdateSubscribers:)`;
> (b) report success to Dart from the original call (the value will
>     be sent eventually) — OR introduce a distinct
>     `notify-backpressure` Pigeon code so callers can choose to
>     pace themselves.

**Add external references:**
- Apple `peripheralManager(_:isReadyToUpdateSubscribers:)`:
  https://developer.apple.com/documentation/corebluetooth/cbperipheralmanagerdelegate/peripheralmanagerisready(toupdatesubscribers:)
- Apple `peripheralManager.updateValue(_:for:onSubscribedCentrals:)`
  return value documentation:
  https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/updatevalue(_:for:onsubscribedcentrals:)
- WWDC 2017 Session 712 "What's New in Core Bluetooth":
  https://developer.apple.com/videos/play/wwdc2017/712/
  (covers `canSendWriteWithoutResponse` and the analogous flow
  control story on the central side; the peripheral side mirrors it).

**Confidence: high.**

---

### Update to I062 — Confirm fix sketch is correct (no diagnostic change)

The reviewer read I062 in detail and confirms the diagnosis and fix
sketch are exactly correct — no change to the entry's content needed.

**Suggested addition to Notes:**

> **2026-04-26 deep-review confirmation:** External review confirms
> the diagnosis is exact and the fix sketch is the correct approach.
> Bundle with I060/I061/I064 per I098 (rewrite spec) for coherent
> single-PR fix.

**Confidence: high.**

---

### Update to I090 — Extend scope: bond/removeBond/requestPhy/requestConnectionParameters bypass too

**Current entry presumably:** captures `connect()` and `disconnect()`
bypassing error translation.

**Extension to add:**

> The same bypass pattern affects:
> - `BlueyConnection.disconnect()` (line 381) — calls `_platform.disconnect`
>   directly, no error translation.
> - `BlueyConnection.bond()` (line 422) — calls `_platform.bond` directly.
> - `BlueyConnection.removeBond()` (line 427) — calls `_platform.removeBond`
>   directly.
> - `BlueyConnection.requestPhy()` (line 443) — calls `_platform.requestPhy`
>   directly.
> - `BlueyConnection.requestConnectionParameters()` (line 457) — calls
>   `_platform.requestConnectionParameters` directly.
>
> Each of these can throw typed platform-interface exceptions
> (`GattOperationTimeoutException`, etc.) that leak unwrapped to
> the caller. Fix bundled into I099 (typed-error-translation
> rewrite spec).

**Add related:** `[I099]`.

**Confidence: high.**

---

## OUT-OF-SCOPE / ALREADY HANDLED

These are review observations that should NOT result in new backlog
entries — they're already captured elsewhere or are not actionable
as backlog items.

- **`LivenessMonitor` is exceptional code.** Praise, not a backlog
  item. No action. (Note: replaced by `PeerSilenceMonitor` in the
  peer-silence branch — see top-of-document branch context. The
  replacement is also exceptional; the praise transfers.)
- **`LifecycleServer.requestStarted/requestCompleted` design is
  excellent (I079 fix).** Already captured as fixed in I079. No action.
- **I097 (client-side OpSlot starvation) becomes fixed once the
  peer-silence branch merges.** The branch's user-op accounting in
  `_runGattOp` (`markUserOpStarted` / `markUserOpEnded` deferring
  scheduled probes while `_pendingUserOps > 0`) is the explicit fix.
  When the branch lands, the CLI should set I097 `status: fixed`
  with the merge SHA and update `last_verified`.
- **Stress test suite is comprehensive.** Praise. No action.
- **Backlog discipline is best-in-class.** Praise. No action.
- **Two parallel APIs at different abstraction levels (`BlueyPlatform.instance`
  vs `Bluey()`)** — partially captured by the no-singleton claim in
  CLAUDE.md vs reality. Worth a discussion but not a backlog entry
  per se; treat as a documentation/CLAUDE.md update.
- **README is internally inconsistent (Phase 3 PLANNED but Phases 4/5
  COMPLETE).** Documentation issue, fold into a separate "documentation
  refresh" task rather than the backlog.
- **`Capabilities.iOS` static has `canBond: false` which is technically
  wrong (iOS does bond, just implicitly).** Subtle; defer to the
  capabilities-matrix discussion in I053/I065.

---

## Verification log

> _The CLI session should append findings here as it verifies each entry.
> Format: `### IXXX — verified | invalidated | partially verified` plus
> a paragraph of what was found._

(empty)

---

## External references — collected reading list

For convenience when writing future fix specs.

**Apple / iOS:**
- CoreBluetooth framework overview:
  https://developer.apple.com/documentation/corebluetooth
- `CBPeripheral.maximumWriteValueLength(for:)`:
  https://developer.apple.com/documentation/corebluetooth/cbperipheral/maximumwritevaluelength(for:)
- `CBCentralManagerOptionRestoreIdentifierKey`:
  https://developer.apple.com/documentation/corebluetooth/cbcentralmanageroptionrestoreidentifierkey
- `CBPeripheralManager`:
  https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager
- `peripheralManager(_:isReadyToUpdateSubscribers:)`:
  https://developer.apple.com/documentation/corebluetooth/cbperipheralmanagerdelegate/peripheralmanagerisready(toupdatesubscribers:)
- Performing Tasks While Your App Is in the Background (CoreBluetooth
  background guide):
  https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetoothLE/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
- Accessory Design Guidelines (R8 BLE):
  https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf
- WWDC 2017 Session 712 ("What's New in Core Bluetooth"):
  https://developer.apple.com/videos/play/wwdc2017/712/

**Android:**
- BluetoothDevice:
  https://developer.android.com/reference/android/bluetooth/BluetoothDevice
- `BluetoothGattCharacteristic.getInstanceId()`:
  https://developer.android.com/reference/android/bluetooth/BluetoothGattCharacteristic#getInstanceId()
- `BluetoothGatt.requestConnectionPriority(int)`:
  https://developer.android.com/reference/android/bluetooth/BluetoothGatt#requestConnectionPriority(int)
- `BluetoothGatt.setPreferredPhy(int, int, int)`:
  https://developer.android.com/reference/android/bluetooth/BluetoothGatt#setPreferredPhy(int,%20int,%20int)
- AOSP gatt_api.h (status code constants):
  https://android.googlesource.com/platform/external/bluetooth/bluedroid/+/master/stack/include/gatt_api.h
- AdvertiseSettings.Builder:
  https://developer.android.com/reference/android/bluetooth/le/AdvertiseSettings.Builder

**BLE specification:**
- Bluetooth SIG specification page:
  https://www.bluetooth.com/specifications/specs/

**Community / reference implementations:**
- Punch Through "Android BLE: The Ultimate Guide":
  https://punchthrough.com/android-ble-guide/
- Punch Through "BLE Write Requests vs. Write Commands":
  https://punchthrough.com/ble-write-requests-vs-write-commands/
- Punch Through "Android BLE Operation Queue":
  https://punchthrough.com/android-ble-operation-queue/
- Martijn van Welie "Making Android BLE Work" series (parts 1-4):
  https://medium.com/@martijn.van.welie/making-android-ble-work-part-1-a736dcd53b02
- Nordic DevZone:
  https://devzone.nordicsemi.com/
- `flutter_blue_plus` (reference Flutter BLE plugin):
  https://github.com/chipweinberger/flutter_blue_plus
- `bluetooth_low_energy_android` (uses `instanceId` for char identity):
  https://github.com/yanshouwang/bluetooth_low_energy
