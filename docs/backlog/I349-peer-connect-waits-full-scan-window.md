---
id: I349
title: Stop peer connect from waiting out the full scan window after a match
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-07-10
related: [I055, I056]
---

## Symptom

Connecting to a known peer always takes at least the full scan window
(default 5 seconds), even when the target starts advertising — and is
discovered — within the first few milliseconds. The same applies to
peer discovery: no probe begins until the scan window has fully
elapsed.

## Location

`bluey/lib/src/peer/peer_discovery.dart` — both `discover` and
`connectTo` start with `await _collectCandidates(scanTimeout)`, which
resolves only when the scan window closes; candidates are probed
strictly afterwards.

## Root cause

Collect-then-probe sequencing. The scan phase and the probe phase are
serialized, so the scan timeout acts as a floor on connect latency
instead of a ceiling on discovery.

## Notes

Surfaced by the 2026-07-10 networking-test audit's address-rotation
scenario test (A.1), which had to move to virtual time because two
`peer.connect()` calls cost ten real seconds against an instant fake.

Fix sketch: probe-as-you-scan — probe each candidate as it is emitted
and complete `connectTo` on the first identity match (cancelling the
scan), keeping the scan timeout as the *failure* bound only. `discover`
can keep collecting for the full window but should overlap probes with
the ongoing scan. Watch for double-probe of duplicate advertisements
(dedup by address) and for the iOS shared-link dedup guidance in
`bluey/docs/cross-platform-quirks.md`.
