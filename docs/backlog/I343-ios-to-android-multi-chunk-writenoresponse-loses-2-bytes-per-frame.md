---
id: I343
title: iOS-central → Android-peripheral multi-chunk `WriteNoResponse` transmissions silently lose exactly 2 bytes per frame at the chunk boundary
category: bug
severity: high
platform: both
status: open
last_verified: 2026-06-02
related: [I050, I338, I339]
---

## Symptom

When the central role on iOS sends a `WriteNoResponse` payload that
exceeds the negotiated per-call write budget (so the consumer-side
encoder splits it into two or more sequential `connection.write(...)`
calls), the bytes that arrive at the Android-peripheral GATT server are
short by **exactly 2 bytes per logical frame**. The two missing bytes
are silently elided at the chunk-boundary in the reassembled byte
stream; the receiver's framing decoder, expecting `length` payload
bytes per the wire's length-prefix, ends up consuming `length - 2`
real-payload bytes plus the first 2 bytes of the *next* frame's magic
prefix (`G`, `S` = `0x47 0x53`, the first two bytes of `GSP1`).

Receiver-side telltale (gossip_bluey's frame decoder):

```
Peer sync error: type=messageCorrupted
  msg=Malformed gossip message from NodeId(...): FormatException:
      Unexpected character (at character 764)
  …,46,53,52,49,58,53,50,46,54,56,51,53,53,49,34,125]}]}GS
                                                          ^
[BLUEY][WARNING] frame decoder recovered from corruption on NodeId(...);
                  discarded 405 bytes
```

The `}]}GS` tail is universal — every corrupted frame ends with the
valid JSON close of the gossip message body (`}]}` of the outermost
object) followed by exactly 2 spurious bytes `GS` that turn out to be
the first 2 bytes of the *following* frame's wire-level magic.

Reproduced 2026-06-02 in the `gossip_chat` dogfood app between a Pixel
6a (Android peripheral, GATT server) and an iPhone (iOS central, GATT
client). bluey was on the `i339-ios-write-flow-control` branch (HEAD
`7d1af52`) — i.e. with the I339 `PendingWriteQueue` +
`canSendWriteWithoutResponse` gate landed on the iOS-central side. The
fix was confirmed live in the binary by a full clean rebuild
(`flutter clean && rm -rf ios/Pods ios/Podfile.lock && pod install`).
Despite the fix, the corruption is **byte-for-byte identical** to
pre-fix runs — same `}]}GS` shape, same recovery-discard magnitudes
(405 / 446 / 68 / 444 / 438 / 2649 bytes) — confirming I339's TX-gate
pacing is not the mechanism at fault.

## Reproduction window

An iOS Dart-isolate hang (the keyboard XPC reconnect when opening a
text field is the easiest trigger — 10.61 s in the captured run)
causes gossip's outbound queue to accumulate state changes from the
hang interval. On resumption gossip flushes a backlog. The first
`DeltaResponse` whose payload exceeds the per-call write budget gets
chunked by gossip_bluey's `FrameEncoder.encode` into two or more
sequential `port.sendData(chunk)` calls — *and that is the first
corrupt frame to land on Android*.

```
iOS Dart (gossip_bluey):
  20:14:35.788  [GOSSIP][DEBUG] SEND DeltaResponse to 294fa569:
                              channel=40b8c82a stream=presence
                              entries=1 (766 bytes)
  20:14:35.797  [BLUEY-EV] [GATT] WriteNoResponse f0000000 (514 bytes)  ← chunk 1
  20:14:35.798  [BLUEY-EV] [GATT] WriteNoResponse f0000000 (260 bytes)  ← chunk 2
                                              514 + 260 = 774
                                                = 8 (header) + 766 (payload)  ✓

Android Dart (gossip_bluey):
  20:14:37.635  [ERROR] Malformed gossip message ...
                FormatException: Unexpected character (at character 764)
                …}]}GS
  20:14:37.688  [BLUEY][WARNING] frame decoder recovered from corruption
                                  on NodeId(...); discarded 405 bytes
```

The encoder math is correct: a 766-byte gossip payload becomes a
774-byte framed buffer (4 magic + 4 length + 766 payload). Chunked at
`chunkSizeFor=514` → `[514, 260]`. The full reassembled wire image on
the receiver is **774 bytes** … if 2 bytes per frame are not silently
dropped. They are.

## What is NOT the cause

- **I338 (Pattern B presence-subscription disconnect detection).**
  Verified by inspection of the same Android log: no `client gone`,
  no `central disconnected`, no `Peer disconnected`. The receiver's
  frame decoder is *not* being torn down by a spurious lifecycle
  disconnect. Pattern B works.
- **I339 (CoreBluetooth `.withoutResponse` flow control).** Verified
  by inspection of `CentralManagerImpl.swift` on
  `i339-ios-write-flow-control` (HEAD `7d1af52`): `PendingWriteQueue`,
  `canSendWriteWithoutResponse` gate at the actual `writeValue` site,
  and `peripheralIsReady(toSendWriteWithoutResponse:)` delegate are
  all present and correct. Clean rebuild confirmed in the binary.
  Corruption signature unchanged from the pre-fix runs. The
  back-to-back ATT-stack saturation hypothesis I339 addresses is not
  the mechanism here.
- **Frame encoder / decoder math.** Spot-checked at the exact reproducer:
  766-byte gossip payload → 774-byte framed buffer → `[514, 260]`
  chunks summing to 774. Decoder reads `length=766` (matching the
  encoder's value) and then reads 766 bytes. The math at both ends
  agrees. The bytes between them don't.
- **Pigeon / `FlutterStandardTypedData` variable-length size prefix
  hypothesis.** If Pigeon were systematically losing 2 bytes per
  `Uint8List` of size ≥ 254, every single-chunk write ≥ 254 bytes
  would also corrupt. They don't: the dogfood log shows hundreds of
  single-chunk writes at 366 / 408 / 449 / 514 bytes — and the
  decoder consumes those frames cleanly.

## What IS the cause (empirically)

**Multi-chunk** frames are uniquely affected. Single-chunk frames
(any gossip message whose framed size is ≤ `chunkSizeFor`) transmit
cleanly through this same code path with no byte loss. As soon as
gossip_bluey emits two sequential `port.sendData(chunk)` calls for the
same frame, the receiver loses exactly 2 bytes off the end of that
frame's payload.

By "off the end": the JSON content in the decoder's failed parse is
intact for `(N − 2)` bytes and only breaks on the last 2, which are
the next-frame's magic spilling forward. The lost bytes are
position-localized to the tail, not scattered.

The two prime mechanisms left after the above:

### Candidate A — `bluey_ios` central side, chunk boundary

Two consecutive `peripheral.writeValue(data, for:characteristic, type: .withoutResponse)`
calls dispatched in quick succession (the `PendingWriteQueue`
correctly drains both while `canSendWriteWithoutResponse` is true)
result in two `ATT_WRITE_CMD` transmissions on the radio. CoreBluetooth
or the iOS BT-stack may be coalescing them — and the documented `.withoutResponse`
contract is that writes "may be silently dropped or coalesced." A
coalescing event that strips a 2-byte boundary marker (or the trailing
2 bytes of the prior packet when the next packet is enqueued before
the prior's ATT-PDU is finalized) matches the symptom exactly.

If this is the locus, the fix is on the iOS side: insert pacing
between consecutive `writeValue` calls *even when
`canSendWriteWithoutResponse` is true* (a small delay, or — better —
require that consecutive writes in a logical frame use
`.withResponse` so the GATT long-write protocol governs the
fragmentation, see Candidate C below).

### Candidate B — `bluey_android` peripheral side, write-request marshalling

`GattServer.kt:906–978` (`onCharacteristicWriteRequest`) wraps each
incoming `value: ByteArray` in a `WriteRequestDto` and posts it to
Dart via `flutterApi.onWriteRequest(...)`. If two `ATT_WRITE_CMD`s
arrive in close succession and the second one's first 2 bytes get
folded into the first one's tail at the platform layer (or the Pigeon
marshalling of `value: ByteArray` has an off-by-2 specifically when
the inbound queue contains a pending follow-up write), the same
symptom appears.

Less likely than Candidate A because (a) the symptom is iOS-as-source
specific (Android-as-source → iOS-as-sink notifications via I040's
`PendingNotificationQueue` work correctly bidirectionally in the same
runs), and (b) the Pigeon size-prefix hypothesis is already ruled out
by the single-chunk-writes-work-fine evidence. But it cannot be
eliminated without instrumentation.

### Candidate C — gossip_bluey consumer side (architectural workaround, not a root-cause fix)

A consumer using only `.withResponse` writes for multi-chunk
transfers would route those writes through the GATT long-write
protocol (`PREPARE_WRITE` + `EXECUTE_WRITE`), which is specified to
preserve byte ordering and has acknowledgment. That sidesteps both
Candidates A and B but at substantial throughput cost. Not the right
upstream fix — listed only to note that the consumer has a
mitigation available while this is being investigated.

## Recommended next step: instrument & bisect

Drop `bluey_android`'s log threshold so the existing DEBUG-level log
at `GattServer.kt:915–926` surfaces every `onCharacteristicWriteRequest`'s
`length` field. Run the same dogfood scenario. Then for each
correlated time-window pair:

```
iOS:     WriteNoResponse f0000000 (514 bytes)
Android: onCharacteristicWriteRequest length=512     ← bytes lost on platform layer
```

vs.

```
iOS:     WriteNoResponse f0000000 (514 bytes)
Android: onCharacteristicWriteRequest length=514     ← bytes lost on Dart-side reassembly
```

The first case localizes the bug to Candidate A or below the
Kotlin/Swift bridge (CoreBluetooth or the Android BT-stack itself).
The second localizes it to Candidate B or higher — Pigeon marshalling
of `WriteRequestDto.value` between Kotlin and Dart, or the consumer's
own buffer-accumulation logic.

Either result narrows the next debugging round to a fully tractable
surface.

## Why severity is high

- **Silent.** No exception, no log, no warning. The Dart `Future` from
  `connection.write(...)` resolves `.success(())` (per I339's
  complete-on-hand-off contract). Both sides believe the write
  succeeded.
- **Triggers on routine user behavior.** Any iOS Dart-isolate stall
  long enough to grow the outbound gossip queue past one
  chunk-size-worth-of-payload — sub-15s is sufficient in the
  reproducer — is enough to manifest. Real apps stall.
- **Permanent for the GATT session.** Once corruption begins, it
  recurs on every subsequent multi-chunk frame from the same iOS
  client. The decoder recovers per-frame but every next multi-chunk
  frame re-tears. No self-heal mechanism: gossip-level retransmits
  re-send the same too-large messages and corrupt again. With I338
  Pattern B now correctly suppressing lifecycle-silence disconnects,
  there is no involuntary disconnect/reconnect to reset the link.
  Application-observable result: **iOS → Android delivery
  unidirectionally dead until the user kills the app**. Confirmed by
  consumer: 10+ minutes after the trigger, with iOS still actively
  attempting sends, Android still sees nothing useful from this
  client.
- **The masking interaction with I338 is significant.** Before I338
  Pattern B landed, the lifecycle-silence pseudo-disconnect would
  tear down the GATT link and force a fresh GATT session on
  reconnect — which incidentally reset whatever stuck state this
  bug introduces. Pattern B is correct, but it removes that
  incidental recovery path. This bug is therefore strictly more
  visible to consumers post-I338 than before, even though it
  pre-dates I338.

## Notes

- The bug existed in pre-I338 runs but was masked by the
  decoder-reset-on-spurious-disconnect path. The visible symptom
  ("post-hang corruption that doesn't self-heal") only appears
  starting with the runs against I338 Pattern B (`bluey` main
  `d173d39` / `a8a807d`) and continues unchanged through the
  I339-fix branch.
- Recovery byte counts in the consumer's frame decoder
  (`gossip_bluey/lib/src/application/services/connection_service.dart:170-176`)
  recur across dogfood runs to the byte: 405 / 446 / 68 / 444 / 438 /
  2649. These are a function of gossip-message-size distribution
  (which is deterministic from the entry log) and the per-frame
  off-by-2, not random noise.
- The interaction between **multi-chunk WriteNoResponse on iOS** and
  **back-to-back ATT_WRITE_CMD reception on Android** is the
  load-bearing surface. The same iOS path serving
  *single*-chunk frames of any size up to ~514 bytes — even hundreds
  of them in tight succession — works correctly. Only the per-frame
  boundary between two consecutive chunks of the same logical frame
  manifests the 2-byte loss.
- Read alongside I050 (prepared-write flow unimplemented for
  long-writes), which would be the obvious lever for Candidate C
  if I339 turns out to be insufficient for the
  fragmented-WriteNoResponse case in general.
