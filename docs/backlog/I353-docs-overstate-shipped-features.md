---
id: I353
title: Correct product docs that advertise unshipped features as complete
category: bug
severity: high
platform: both
status: open
last_verified: 2026-07-10
related: [I035]
---

## Symptom

README marks "Phase 2: Android Platform COMPLETE" with checkmarks for
bonding, PHY configuration, and connection-parameter control — none of
which ship on any platform (Android throws `UnimplementedError`, iOS
exposes no such API). CLAUDE.md's glossary still lists the removed
`disconnectCentral` and quotes a stale test count.

## Location

`README.md:7-8,23-25`; `CLAUDE.md` glossary + header. (2026-07-07
audit **DA-01** — the audit's sole MAJOR.)

## Notes

The runtime is honest (capability gating works); this is purely a
documentation defect, but it is the first thing a consumer reads and
they may select the library for capability it does not have. Fix: mark
bond/PHY/conn-params as planned (Stage B,
[I035](I035-android-bond-phy-conn-param-stubs.md)), correct the
glossary and counts.
