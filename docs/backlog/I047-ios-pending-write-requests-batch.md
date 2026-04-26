---
id: I047
title: iOS `respondToWriteRequest` only responds to first of batched ATT requests
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-04-26
related: [I050]
---

## Symptom (suspected — confidence low)

When a central performs a long write (BLE prepare-write/execute-write flow) against a hosted characteristic on iOS, the server may receive multiple `CBATTRequest` objects representing the parts of the long write. The plugin stores these as a list under a single Dart-visible `requestId`. When Dart calls `respondToWriteRequest`, only `requests.first` is passed to `peripheralManager.respond(...)`. The remaining parts (if iOS pre-staged them) are silently dropped.

A separate but related concern: in `didReceiveWrite`, Flutter is notified once per `CBATTRequest` in the array (loop at line 333), all sharing the same `requestId`. A consumer-side handler that calls `respondToWriteRequest` once per notification will see only the first call succeed — subsequent calls fail with `notFound` because the entry was already `removeValue`'d.

The net effect — if the hypothesis is correct — is that long writes to hosted iOS services either time out at the ATT layer or complete successfully if the central is permissive about partial responses.

## Location

`bluey_ios/ios/Classes/PeripheralManagerImpl.swift:165-172` (response side); `:330` (request batching at receive time).

```swift
guard let requests = pendingWriteRequests.removeValue(forKey: requestId), let firstRequest = requests.first else {
    completion(.failure(BlueyError.notFound.toServerPigeonError()))
    return
}
peripheralManager.respond(to: firstRequest, withResult: status.toCBATTError())
```

The data structure (`[Int: [CBATTRequest]]`) clearly anticipates multiple requests per requestId — but the response loop is missing.

## Root cause (suspected)

Either the batching code was added in anticipation of long-write support without completing the response side, OR Apple's documented behaviour for `respond(to:withResult:)` is "respond to the first; the framework handles the rest" — in which case the multi-notification on the Dart side is the bug, not the single-response.

## Notes

**Verification steps before fixing:**

1. Find where `pendingWriteRequests[requestId]` is populated — `didReceiveWrite` at line 319 confirms it stores the array as-is. Each request in the array becomes its own Flutter notification with the *same* requestId (line 333 loop).
2. Read Apple's documentation on [`respond(to:withResult:)`](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/respond(to:withresult:)) more carefully than the reviewer did. Apple's contract may mean responding to the first request in an array is correct on the wire; in that case the bug shifts to the Dart-side notification fan-out.
3. If Apple's contract requires per-request response, then the response loop is the bug.
4. Either way, add a unit test using `nRF Connect` configured for a long write to confirm.

This finding is bundled with I050 (prepared-write flow unimplemented) which already exists in the backlog as a known gap on the **central** side. I047 is the corresponding **server-side** gap for the same protocol. Either close I047 if the server-side path isn't actually broken, or fold into I050 as a coherent long-write support spec.

External references:
- BLE Core Specification 5.4, Vol 3, Part F, §3.4.6: Prepare Write Request, Execute Write Request, Prepare Write Response.
- Apple [`CBPeripheralManager.respond(to:withResult:)`](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/respond(to:withresult:)).
