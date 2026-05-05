---
id: I329
title: `MockAndroidConnectionExtensions` and `_FakeAndroidConnectionExtensions` implement `requestMtu` with different semantics
category: enhancement
severity: low
platform: domain
status: open
last_verified: 2026-05-05
related: [I325]
---

## Symptom

After I325 introduced the `MockAndroidConnectionExtensions` (in `bluey/test/connection_test.dart`) and `_FakeAndroidConnectionExtensions` (in `bluey/example/test/fakes/fake_connection.dart`) test fixtures, the two implement `requestMtu` slightly differently:

- **Mock** (`bluey/test/connection_test.dart:11-16`):
  ```dart
  Future<Mtu> requestMtu(Mtu desired) async {
    final negotiated = desired.value > 512 ? 512 : desired.value;
    mtu = Mtu.fromPlatform(negotiated);
    return mtu;
  }
  ```
- **Fake** (`bluey/example/test/fakes/fake_connection.dart:18-22`):
  ```dart
  Future<Mtu> requestMtu(Mtu desired) async {
    mtu = Mtu.fromPlatform(desired.value);
    return mtu;
  }
  ```

The mock caps at 512 (simulating Android's BLE-spec maximum); the fake doesn't. A test author moving between the two could be surprised by different return values for the same input.

## Location

- `bluey/test/connection_test.dart:11-16` — `MockAndroidConnectionExtensions.requestMtu`.
- `bluey/example/test/fakes/fake_connection.dart:18-22` — `_FakeAndroidConnectionExtensions.requestMtu`.

## Fix sketch

Three options:

1. **Cap both at 512** — match the BLE-spec maximum, consistent with what the platform would actually do. Behaviorally most accurate.
2. **Cap neither** — both pass through `desired.value` verbatim. Simpler, but misleading for tests asserting on platform-realistic behavior.
3. **Cap based on capabilities** — use the `Capabilities.maxMtu` value (Android 517, iOS 185). Most realistic but introduces a capability dependency in the fake.

Recommend option 3 if both fakes are aligned, or option 1 as a simpler harmonization.

## Why low severity

- Cosmetic / consistency. No correctness implication for any current test.
- Discovered during the I325 audit; tests in both files pass with the current shapes.

## Notes

When fixing, also align `MockAndroidConnectionExtensions` and `_FakeAndroidConnectionExtensions`'s other stubbed members (currently both return identical defaults). The drift is recent (introduced together by I325); easier to keep them in sync now than after they've diverged further.
