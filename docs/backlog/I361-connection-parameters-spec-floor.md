---
id: I361
title: Apply the BLE-spec x2 factor to the supervision-timeout floor
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-07-10
---

## Symptom

`ConnectionParameters` accepts timeout/latency/interval triples the
controller will reject: its invariant uses
`minTimeout = (1 + latency) * interval` where the spec (Core Vol 6
Pt B 4.5.2) requires the doubled product (audit DA-13).

## Location

`bluey/lib/src/connection/connection_parameters.dart:26`.

## Notes

Add the factor; pin with a boundary-value test. Only reachable via the
Android connection-parameters API (currently Stage-A stubbed — see
[I032](I032-android-connection-parameters-stub.md)), so graded low
until that ships.
