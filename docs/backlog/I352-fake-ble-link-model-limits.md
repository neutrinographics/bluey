---
id: I352
title: Extend FakeBleLink to cover descriptors, duplicate UUIDs, indication acks, and MTU sync
category: limitation
severity: low
platform: domain
status: open
last_verified: 2026-07-10
related: [I346]
---

## What this is

`FakeBleLink` (the virtual BLE link that lets two real Bluey endpoints
exchange traffic end-to-end, audit R4) deliberately models the surface
the current tests need. Its known gaps, today recorded only as code
comments:

- **Descriptor operations are not routed over the link** — a client
  `readDescriptor`/`writeDescriptor` against a linked device hits the
  client-local store instead of surfacing on the server side.
- **Duplicate-UUID service trees are unsupported** — notification
  delivery resolves the client-side handle by UUID, first instance
  wins.
- **Indication acknowledgments are not modeled** — `indicate*` delivers
  like a notify; there is no ack round-trip the server side waits on.
- **MTU is fixed at link setup** — a client `requestMtu` does not
  update the MTU the server side sees for the central.

## Why it matters

The next scenario that reaches for the link and touches one of these
(e.g. a CCCD-descriptor test over a real link, or an indication-ack
flow-control test) will discover the edge by surprise. Recording the
limits makes the gap a choice instead of a trap, and this entry is the
place to extend the model when a scenario needs it.

## Rough approach

Extend on demand, one gap per need: route descriptor ops through
server-side request streams the way reads/writes already route; carry
the client-side handle through link delivery instead of resolving by
UUID; add an ack round-trip for indications (server future completes on
client ack); propagate `requestMtu` results to the server-side central
record.

## Related

- The link: `bluey/test/fakes/fake_platform.dart` (`FakeBleLink`); shared-link topology in [I346](I346-fake-platform-shared-link-trap-model.md).
- [Testing conventions](../testing-conventions.md) — fixture overview.
