---
id: I205
title: iOS 16+ `UIDevice.current.name` returns generic model name
category: limitation
severity: low
platform: ios
status: wontfix
last_verified: 2026-04-23
---

## Rationale

Starting with iOS 16, `UIDevice.current.name` returns a generic model string ("iPhone", "iPad") instead of the user-assigned name ("Joel's iPhone"). Accessing the real name requires the `com.apple.developer.device-information.user-assigned-device-name` entitlement, which needs Apple's approval.

Apps that want to use the device name as a default for advertising or display get a generic value.

## Decision

Wontfix for the library. Applications that actually need the user-assigned name can apply to Apple for the entitlement and pass the name in at runtime. Bluey uses whatever name the app provides for advertising.

## Notes

Not applicable if the app provides an explicit advertised name via `startAdvertising(name: ...)`. Only a concern if the library were trying to auto-populate a default name from `UIDevice`.
