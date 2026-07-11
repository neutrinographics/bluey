---
id: I346
title: Model the iOS shared-link trap in the fake platform so bidirectional-discovery scenarios are testable
category: enhancement
severity: low
platform: domain
status: fixed
last_verified: 2026-07-10
fixed_in: r12-fake-modeling merge
related: [I337, I338]
---

## What this is

On iOS, a pair of devices shares **one physical Bluetooth link** no matter how
many logical roles run over it. If device B is already serving device A as a
client and then B *also* connects out to A (because B's scanner saw A's
advertisement), disconnecting that second, outgoing handle tears down the one
shared physical link — killing the original serving relationship too. This is
the number-one consumer trap documented in the cross-platform quirks guide,
complete with a recommended address-based dedup pattern apps must follow.

The in-memory test platform (`FakeBlueyPlatform`) cannot express any of this:
its client role and server role are two disconnected fixtures, so "a peer that
is simultaneously my client and my connection target over one shared link" is
unrepresentable, and the documented dedup pattern has no automated test.

## Why it matters

The dedup guidance exists because getting it wrong produces a
connect/disconnect/reconnect loop in real apps. Right now the only way to
verify that guidance — or any library behavior around shared links — is two
physical iPhones. Modeling the shared link in the fake turns the quirk doc's
recommended pattern into a regression-tested contract, and lets the peer
lifecycle (identification clearing and re-emission around the loop) be
exercised deterministically.

## Rough approach

Extend the fake with an opt-in "shared link" association between a simulated
peripheral (client role) and a connected central (server role) that represent
the same physical peer. Disconnecting either side of an associated pair tears
down both, mirroring iOS; leaving them unassociated preserves today's
Android-like independent-links behavior. Depends on the two roles being wired
to each other at all (the audit's R4 loopback recommendation) — sequence this
after that lands.

## Related

- Consumer-facing description of the trap: [cross-platform quirks](../../bluey/docs/cross-platform-quirks.md) §"iOS shares one LL connection per peer pair across GAP roles".
- Audit that identified the gap: [2026-07-10 networking-scenario test audit](../reviews/2026-07-10-networking-scenario-test-audit.md) (addendum scenario 9; builds on finding NT-6 / recommendation R4).
- [I337 — client-id mismatch between peer connections and disconnections](I337-client-id-mismatch-between-peerconnections-and-disconnections.md) (the dedup pattern bridges these address types), [I338 — lifecycle silence / disconnect reconciliation](I338-lifecycle-silence-emits-disconnect-without-gatt-teardown.md) (the identification loop the trap keeps re-triggering).
