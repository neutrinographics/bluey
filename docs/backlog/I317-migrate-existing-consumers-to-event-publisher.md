---
id: I317
title: Migrate BlueyServer / BlueyScanner / Bluey to depend on EventPublisher (not BlueyEventBus)
category: limitation
severity: low
platform: domain
status: fixed
last_verified: 2026-05-01
fixed_in: 84a04dd
related: [I054, I068]
---

## Symptom

Three existing aggregates depend on the concrete `BlueyEventBus` class
instead of the new `EventPublisher` port introduced in the I054 / I068
bundle:

- `BlueyServer` — takes `BlueyEventBus` in its constructor
  (`bluey/lib/src/gatt_server/bluey_server.dart:75`).
- `BlueyScanner` — takes `BlueyEventBus` in its constructor
  (`bluey/lib/src/discovery/bluey_scanner.dart`).
- `Bluey` itself — owns the bus and threads it as `BlueyEventBus`
  rather than `EventPublisher` to those aggregates.

Aggregates that emit events should depend only on the smallest
interface they need (`EventPublisher.emit`), per the Interface
Segregation Principle. Depending on the concrete bus pulls in `stream`
(a consumer concern) and `close` (an orchestrator concern) that the
aggregate never invokes — Clean Architecture violation.

## Location

- `bluey/lib/src/gatt_server/bluey_server.dart` — constructor field
  `_eventBus` typed as `BlueyEventBus`.
- `bluey/lib/src/discovery/bluey_scanner.dart` — same shape.
- `bluey/lib/src/bluey.dart` — passes `_eventBus` (concrete) into
  `BlueyServer` and `BlueyScanner`.

## Root cause

Pre-existing pattern: when the event bus was introduced, no abstract
port was extracted. The concrete class served as both port and
implementation. The I054 / I068 bundle introduced `EventPublisher` for
new threading (`BlueyConnection`, `LifecycleClient`, `LifecycleServer`)
but did not migrate the existing consumers — left as a transitional
inconsistency to keep that bundle scoped.

## Notes

Fixed in `84a04dd`. Two-line diff:
- `BlueyServer._eventBus` field type changed from `BlueyEventBus` to
  `EventPublisher`.
- `BlueyScanner._eventBus` field type same change.

`Bluey` keeps `_eventBus` typed as `BlueyEventBus` because it owns
the bus's full lifecycle: it exposes `stream` via the public `events`
getter and calls `close()` during `dispose()`. Passing `_eventBus`
into the aggregates now works via implicit upcast through the
`BlueyEventBus implements EventPublisher` relation (introduced in
`14bae42`).

No tests modified — none of the existing tests cared about the
concrete type. After this lands, every aggregate in the codebase
that emits events depends on `EventPublisher`. The concrete bus is
only mentioned at the orchestrator (`Bluey`).
