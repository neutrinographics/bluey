---
id: I301
title: ConnectionParameters and mtu use primitives where domain value objects would carry validation
category: limitation
severity: low
platform: domain
status: open
last_verified: 2026-04-26
related: [I089, I300]
---

## Symptom

Several BLE-spec-bounded numeric quantities are typed by their primitive types with valid ranges documented only in doc-comments:

- `ConnectionParameters.intervalMs: double` — spec range 7.5ms to 4000ms (per `Connection.connectionParameters` doc-comment).
- `ConnectionParameters.latency: int` — spec range 0 to 499.
- `ConnectionParameters.timeoutMs: int` — spec range 100ms to 32000ms, with the additional invariant `timeoutMs > (1 + latency) * intervalMs` (per the doc-comment).
- `Connection.mtu: int` — spec range 23 to 517 on Android, 23 to 185 on iOS. Platform-asymmetric upper bound.

A consumer constructing `ConnectionParameters(intervalMs: 5000, latency: 600, timeoutMs: 50)` gets a runtime construction with no validation. The library delegates validation to the platform, which throws platform-specific errors at request time. The doc-comment invariants are not enforced.

## Location

- `bluey/lib/src/connection/connection.dart:36-78` — `ConnectionParameters` class.
- `bluey_platform_interface/lib/src/platform_interface.dart:46-56` — `PlatformConnectionParameters` mirror.
- `bluey/lib/src/connection/connection.dart:159` — `mtu` getter (primitive `int`).

## Root cause

Value-object discipline costs more in Dart than in languages with cheap newtype wrappers (Rust, Haskell, F#). The primitive-typed fields work; the cost only shows up when an invalid value reaches the platform and produces a confusing error.

## Notes

The DDD-pure shape introduces value objects that enforce spec invariants at construction:

```dart
@immutable
class ConnectionInterval {
  final double milliseconds;
  const ConnectionInterval(this.milliseconds)
      : assert(milliseconds >= 7.5 && milliseconds <= 4000,
            'connection interval out of spec range (7.5–4000 ms)');
}

@immutable
class PeripheralLatency {
  final int events;
  const PeripheralLatency(this.events)
      : assert(events >= 0 && events <= 499,
            'peripheral latency out of spec range (0–499 events)');
}

@immutable
class SupervisionTimeout {
  final int milliseconds;
  const SupervisionTimeout(this.milliseconds)
      : assert(milliseconds >= 100 && milliseconds <= 32000,
            'supervision timeout out of spec range (100–32000 ms)');
}

@immutable
class ConnectionParameters {
  final ConnectionInterval interval;
  final PeripheralLatency latency;
  final SupervisionTimeout timeout;

  ConnectionParameters({
    required this.interval,
    required this.latency,
    required this.timeout,
  }) {
    // Cross-field invariant from the BLE spec:
    final minTimeout = (1 + latency.events) * interval.milliseconds;
    if (timeout.milliseconds <= minTimeout) {
      throw ArgumentError(
        'supervision timeout must exceed (1 + latency) * interval '
        '($minTimeout ms); got ${timeout.milliseconds} ms',
      );
    }
  }
}
```

`Mtu` is more interesting because of platform asymmetry:

```dart
@immutable
class Mtu {
  final int value;
  const Mtu._(this.value);

  factory Mtu(int value, {required Capabilities capabilities}) {
    if (value < 23) {
      throw ArgumentError('MTU must be ≥ 23 (BLE spec minimum)');
    }
    if (value > capabilities.maxMtu) {
      throw ArgumentError(
        'MTU $value exceeds platform maximum ${capabilities.maxMtu}',
      );
    }
    return Mtu._(value);
  }

  /// The minimum guaranteed across all platforms.
  static const Mtu minimum = Mtu._(23);
}
```

This is the kind of value-object that earns its keep — the `Capabilities` parameter forces the construction site to confront the platform-asymmetric upper bound, eliminating an entire class of "user requested 517-byte MTU on iOS" support tickets.

## Cost-benefit

This is a refinement, not a critical fix. The existing primitive-typed code works. The benefit is:

- Construction-time validation surfaces errors immediately at the call site rather than later at the platform call.
- The cross-field invariant (`timeout > (1 + latency) * interval`) becomes enforced, not just documented.
- The platform-asymmetric Mtu bound is encoded in the type, not in prose.
- Reading code that handles connection parameters, the type names carry domain meaning rather than just "ms" suffix conventions.

The cost is more files, more imports, more `Mtu.value` / `interval.milliseconds` accesses at use sites.

This is best addressed during one of the larger Connection-aggregate refactors (I089 or I300) — coherent shapes are easier to review than piecemeal refinements.

External references:
- Eric Evans, *Domain-Driven Design* (2003), Chapter 5: "A Model Expressed in Software" — value objects, invariants, and immutability.
- Vaughn Vernon, *Implementing Domain-Driven Design* (2013), Chapter 6: "Value Objects" — practical value-object design, including validation in constructors.
- Martin Fowler, [Primitive Obsession](https://refactoring.guru/smells/primitive-obsession).
- Bluetooth Core Specification 5.4, Vol 6 (Low Energy Controller), Part B, §4.5.2: "LE Connection Parameters" — the canonical source for the spec ranges.
- [Apple Accessory Design Guidelines](https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf) (R8 BLE), §3.6: connection parameter recommendations for iOS.
