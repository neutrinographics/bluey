---
id: I356
title: Stop the peer upgrade conflating transient failures with 'not a peer' or fabricating identity
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-07-10
related: [I304]
---

## Symptom

Two dishonest failure modes in the peer upgrade (audit DA-06, DA-07):
a transient GATT failure during upgrade becomes a permanent
`NotABlueyPeerException`, and a failed ServerId read with the control
service present silently fabricates a random identity — defeating the
stable-identity guarantee that is the Peer module's reason to exist.

## Location

`bluey/lib/src/bluey.dart` — `_tryBuildPeerConnection`'s outer
`catch (_)` returning null, and `serverId ?? ServerId.generate()`.

## Notes

Only the explicit "control service absent" branch may map to
not-a-peer; transient discovery/read errors propagate. "Control
service present but identity unreadable" is an explicit failure — never
mint an identity the caller might persist. Note: mid-session identity
*changes* are already handled (mismatch = disconnect, 2026-07-10);
this item is about establishment-time honesty.
