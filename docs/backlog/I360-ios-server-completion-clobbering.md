---
id: I360
title: Queue or reject concurrent iOS addService/startAdvertising completions
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-07-10
related: [I081]
---

## Symptom

`addService` / `startAdvertising` store their completion handlers in
single-value slots; a concurrent or duplicate call overwrites the
first caller's completion, orphaning its `Future` forever (audit
DA-12, latent). Android's equivalent advertise race is
[I081](I081-advertiser-concurrent-start.md).

## Location

`bluey_ios/ios/Classes/PeripheralManagerImpl.swift` —
`addServiceCompletions` keyed by UUID; `startAdvertisingCompletion`
single optional.

## Notes

Queue completions (OpSlot-style) or reject a second in-flight call.
Now directly testable via the R5 delegate seam
(`PeripheralManagerImplCoreTests`).
