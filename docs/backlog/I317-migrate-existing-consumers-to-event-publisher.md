---
id: I317
title: Migrate BlueyServer / BlueyScanner / Bluey to depend on EventPublisher (not BlueyEventBus)
category: limitation
severity: low
platform: domain
status: open
last_verified: 2026-05-01
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

Mechanical migration:

1. Change each aggregate's field type from `BlueyEventBus` to
   `EventPublisher`. Constructor parameter type matches.
2. `Bluey` keeps `_eventBus` typed as `BlueyEventBus` because it owns
   the lifecycle (`close()`) and exposes `events` (`stream`). When
   passing it into aggregates, Dart upcasts implicitly via the
   `BlueyEventBus implements EventPublisher` relation.
3. Test fakes that mocked `BlueyEventBus` keep working — they extend
   the same class.

After this lands, every aggregate in the codebase that emits events
will depend on `EventPublisher`, not on the concrete bus. The bus is
only mentioned at the orchestrator (`Bluey`) and at construction
sites that wire it through.

Estimated effort: 1 hour. Pure refactor — no behavior change, no test
changes. The risk is finding a place that uses the bus's `stream` /
`close` from inside an aggregate (which would be a separate bug —
those are orchestrator concerns and shouldn't be there).
