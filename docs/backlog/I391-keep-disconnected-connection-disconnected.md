---
id: I391
title: Keep a disconnected Connection disconnected
category: bug
severity: low
platform: domain
status: fixed
last_verified: 2026-11-18
fixed_in: 3e6a653
related: [I381]
---

## Symptom

A platform stream that re-emits can move a `disconnected` connection back to `linked`.

## Location

`bluey/lib/src/connection/bluey_connection.dart:526` — `_setState`.

## Root cause

Found by reading. `_setState` blocks only the `ready` to `linked` move, so no rule says a disconnected connection stays so.

## Notes

Found by finding L6 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 1 (link lifecycle) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Falls out of the link state machine that fixes [I381](I381-remote-disconnect-never-finalises-connection.md), where `disconnected` is terminal. Closes in slice 1. No known-defect test yet.

## Fixed (2026-11-18)

Fixed in `3e6a653` by slice 1 (link lifecycle, [design](../superpowers/specs/2026-11-18-link-lifecycle-design.md) section 6.3): an end state of `Link` is final, so no later platform report revives it, and a `connecting` or `connected` report no longer changes a live link's state. Proved by `an ended link ignores every input` in `bluey/test/features/connection/domain/link_test.dart` and, through the public API, by `a dropped Connection stays disconnected when the platform reports the device connected again` in `bluey/test/bluey_connect_test.dart` (`4393af9`).
