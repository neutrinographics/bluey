---
id: I376
title: Fix the example app where it teaches the wrong patterns
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-07-10
---

## Symptom

The reference app contradicts the library's own guidance (audit
DA-40..DA-42, N4..N6): it scans and serves simultaneously with no
iOS shared-link dedup guard (the exact documented trap); the
"heartbeat tolerance" setting is threaded through four layers then
dropped (and the app uses `connect()`, which has no such parameter);
disconnect control flow is keyed off a string literal matched across
two files; plus small dead widgets and a mislabeled units field.

## Notes

Guard the connect path with `isClientConnected` (and comment why);
route the tolerance setting through `connectAsPeer(peerSilenceTimeout:)`
or remove the control; model the disconnect reason as an enum. The app
is the first code consumers copy — reference quality is the point.
