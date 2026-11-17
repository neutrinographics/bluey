---
id: I387
title: Stop announcing our own outgoing links as clients
category: bug
severity: low
platform: android
status: open
last_verified: 2026-11-17
---

## Symptom

A peripheral this device connects to as a client can appear as a phantom `Client` on our own server.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:737-765`.

## Root cause

Found by reading; needs a device check. The server callback announces every new link as a central, and Android also fires it for links this device opened as a client.

## Notes

Found by finding L2 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 5 (server and peer) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Fix would recognise links the connection manager already owns and not announce them. Closes in slice 5. No known-defect test yet.
