---
id: I203
title: iOS rotates BLE addresses per connection
category: limitation
severity: low
platform: ios
status: wontfix
last_verified: 2026-04-23
---

## Rationale

iOS uses random resolvable BLE addresses for privacy. Each connection from a given iPhone may use a different address. Consequences:

- The same iPhone may appear as multiple connected clients on a remote server (especially an Android server, which sees MAC addresses).
- Stale client entries from previous connections with old rotated addresses persist; they'll never get a disconnect event because the physical peer is gone but the entry is keyed by the old address.
- There's no API to correlate two different random addresses to the same physical device.

## Current mitigation

Combined with I202 and I201, the lifecycle control service catches most of this: rotated-address zombies time out via heartbeat after `lifecycleInterval`. Not perfect (short-session zombies can accumulate faster than they time out), but bounded.

## Decision

Wontfix — platform privacy design. Users accept that Android servers may see "multiple" iPhones that are actually one.

## Notes

Application-level identity (as opposed to address identity) is the fix. Bluey's peer identity system (`BlueyPeer`) is the right place to track logical peers across rotated addresses, provided the peer has a stable application ID exchanged over GATT.
