---
id: I363
title: Reject or chain connect() during an in-flight disconnect
category: bug
severity: medium
platform: android
status: open
last_verified: 2026-07-10
related: [I060]
---

## Symptom

A `connect` issued while the same device's disconnect is still pending
returns idempotent success (the `connections` map still holds the old
gatt), then the arriving `STATE_DISCONNECTED` tears the "new"
connection down (audit DA-18, latent).

## Location

`bluey_android/.../ConnectionManager.kt` — `connect` checks
`connections` but not `pendingDisconnects`.

## Notes

Reject with a typed error or chain the connect behind the disconnect's
completion when `pendingDisconnects` contains the device. Deterministic
to test with the existing Kotlin harness.
