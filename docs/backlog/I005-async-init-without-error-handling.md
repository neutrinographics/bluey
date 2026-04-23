---
id: I005
title: Async initialization without error handling
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-23
historical_ref: BUGS-ANALYSIS-#13
---

## Symptom

`BlueyConnection`'s constructor fires three fire-and-forget futures (`getBondState`, `getPhy`, `getConnectionParameters`). If any rejects, the error is unhandled and logs as a Flutter zone error; getters meanwhile return whatever default was assigned.

## Location

`bluey/lib/src/connection/bluey_connection.dart:212-239` — the three `.then(...)` chains lack `.catchError(...)` or `.onError(...)`.

## Root cause

Constructors can't be async, but the code wants to populate initial property values from platform queries. The compromise is an unsupervised async kickoff. No completer is exposed, so callers can't `await` initialization.

## Notes

Fix sketch: a `static Future<BlueyConnection> create(...)` factory that `Future.wait`s the three queries, catches each independently (a failed PHY read shouldn't block bond state), and passes the results into a private constructor. `Bluey.connect()` would await this factory before returning.

On platforms where these queries are inherently unsupported (iOS does not expose bonding/PHY/connection-parameters via CoreBluetooth — see I200), the platform layer should return defaults synchronously rather than error, so the factory wait is fast.
