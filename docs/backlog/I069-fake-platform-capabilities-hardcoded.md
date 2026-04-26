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

## Symptom

`FakeBlueyPlatform` declares `_capabilities` as a `final` field with hardcoded values (`canScan: true, canConnect: true, canAdvertise: true`). Tests cannot swap in iOS-style capabilities (`canBond: false`, `canRequestPhy: false`, etc.) to exercise the capability-gated code paths.

Combined with I065 (no production code consults capabilities), this means the test suite has zero coverage of "what does my code do when a feature isn't supported on this platform?" The only such case is implicit (I035 silent stubs), which silently passes tests.

## Location

`bluey/test/fakes/fake_platform.dart:36-40`.

## Root cause

The fake was designed before capability gating was added as an architectural concern. It models the union of features (everything supported), not the intersection.

## Notes

Refactor the fake to accept a `Capabilities` in its constructor:

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

Once available, add tests that exercise expected `UnsupportedOperationException` behavior for each capability-gated method. This is the test-side counterpart of I065's "make capabilities load-bearing" goal.
