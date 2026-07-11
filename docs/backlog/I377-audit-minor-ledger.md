---
id: I377
title: Work through the 2026-07-07 audit MINOR ledger
category: refactor
severity: low
platform: both
status: open
last_verified: 2026-07-10
---

## What this is

The 2026-07-07 full-stack audit's MINOR section is a ledger of ~30
real, cheap, low-risk fixes (API-contract nits, robustness guards,
DRY/naming) that are too small to carry as individual roadmap items:
missing `DescriptorNotFoundException`, CQS violations on
`tryUpgrade`/`notifications`, NaN-admitting float VOs, iOS
`authorize()` inferring permission from power state, Kotlin
scanner/log/cleanup hygiene, and friends.

## Notes

The ledger itself lives in
`docs/reviews/2026-07-07-full-stack-audit.md` (MINOR section) — work
through it top to bottom in one or two passes, checking items off
against the audit doc. Anything that grows teeth on contact gets
promoted to its own backlog entry.
