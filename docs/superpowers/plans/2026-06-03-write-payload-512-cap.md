# Clamp write-payload limit to the 512-octet attribute cap (I343) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop iOS→Android `WriteNoResponse` corruption by clamping `maxWritePayload` to the BLE spec's 512-octet maximum attribute-value length.

**Architecture:** A single clamp in the `WritePayloadLimit.fromPlatform` factory — the one funnel both platforms' `getMaximumWriteLength` results pass through. `min(reported, 512)` enforces the protocol invariant in the domain value object; no native changes, pure Dart-testable.

**Tech Stack:** Dart (`bluey` domain), `flutter test`.

**Spec:** `docs/superpowers/specs/2026-06-03-write-payload-512-cap-design.md`

---

## Pre-step: branch

- [ ] Create the branch off `main`:

```bash
cd /Users/joel/git/neutrinographics/bluey
git checkout main && git checkout -b i343-write-payload-512-cap
```

---

## File Structure

- **Modify** `bluey/lib/src/connection/value_objects/write_payload_limit.dart` — add the `maxAttributeValueLength = 512` constant + clamp in `fromPlatform`.
- **Modify** `bluey/test/connection/value_objects/write_payload_limit_test.dart` — unit cases for the clamp.
- **Modify** `bluey/test/connection/max_write_payload_test.dart` — one integration case (fake reports > 512 → clamped).
- **Modify** `bluey/docs/cross-platform-quirks.md` — note the 512 cap.
- **Modify** `docs/backlog/I343-ios-to-android-multi-chunk-writenoresponse-loses-2-bytes-per-frame.md` — status → fixed.

---

## Task 1: Clamp in `WritePayloadLimit.fromPlatform`

**Files:**
- Modify: `bluey/lib/src/connection/value_objects/write_payload_limit.dart`
- Test: `bluey/test/connection/value_objects/write_payload_limit_test.dart`

- [ ] **Step 1: Write the failing tests**

Append this group inside `main()` in `write_payload_limit_test.dart` (after the existing `WritePayloadLimit` group's closing `});` — i.e. before the final `}`):

```dart
  group('WritePayloadLimit.fromPlatform clamps to the 512-octet attribute cap (I343)', () {
    test('clamps a value above 512 down to 512', () {
      // iOS over-reports maximumWriteValueLength(.withoutResponse) as MTU-3
      // (514 @ MTU 517); the BLE spec caps an attribute value at 512 octets
      // and Android silently truncates the overflow. See I343.
      expect(WritePayloadLimit.fromPlatform(514).value, equals(512));
      expect(WritePayloadLimit.fromPlatform(513).value, equals(512));
      expect(WritePayloadLimit.fromPlatform(1000).value, equals(512));
    });

    test('leaves 512 and below unchanged', () {
      expect(WritePayloadLimit.fromPlatform(512).value, equals(512));
      expect(WritePayloadLimit.fromPlatform(511).value, equals(511));
      expect(WritePayloadLimit.fromPlatform(182).value, equals(182));
      expect(WritePayloadLimit.fromPlatform(20).value, equals(20));
    });

    test('preserves the platform "unavailable" sentinels (0, -1)', () {
      // The clamp only ever lowers values above 512.
      expect(WritePayloadLimit.fromPlatform(0).value, equals(0));
      expect(WritePayloadLimit.fromPlatform(-1).value, equals(-1));
    });

    test('exposes the cap as a constant', () {
      expect(maxAttributeValueLength, equals(512));
    });
  });
```

- [ ] **Step 2: Run, verify it fails**

Run: `cd bluey && flutter test test/connection/value_objects/write_payload_limit_test.dart`
Expected: FAIL — `maxAttributeValueLength` undefined, and `fromPlatform(514).value` is `514` not `512`.

- [ ] **Step 3: Implement the constant + clamp**

In `bluey/lib/src/connection/value_objects/write_payload_limit.dart`, add the constant above the class (after the `import`), and clamp inside `fromPlatform`:

```dart
import 'package:meta/meta.dart';

/// The Bluetooth Core Spec (Vol 3, Part F §3.2.9) caps the length of an
/// attribute value at **512 octets**, independent of the negotiated ATT MTU.
/// A central must not write a single value larger than this: spec-conforming
/// peripherals silently truncate the overflow (e.g. Android's fixed
/// `GATT_MAX_ATTR_LEN` receive buffer), and because a Write Command carries no
/// response the loss is invisible. iOS's
/// `maximumWriteValueLength(for: .withoutResponse)` reports `MTU - 3` *without*
/// applying this cap (514 @ MTU 517), so [WritePayloadLimit.fromPlatform]
/// clamps to it. See backlog I343.
const int maxAttributeValueLength = 512;
```

Then change the `fromPlatform` factory (currently `=> WritePayloadLimit._(value);`) to:

```dart
  /// Bypasses positive-value validation (the platform is authoritative about
  /// the negotiated payload limit), but enforces the spec's 512-octet
  /// attribute-value cap — see [maxAttributeValueLength] / I343. The clamp only
  /// lowers values above 512; platform "unavailable" sentinels (0, -1) and all
  /// sub-512 values pass through unchanged.
  factory WritePayloadLimit.fromPlatform(int value) => WritePayloadLimit._(
        value > maxAttributeValueLength ? maxAttributeValueLength : value,
      );
```

- [ ] **Step 4: Run, verify it passes**

Run: `cd bluey && flutter test test/connection/value_objects/write_payload_limit_test.dart`
Expected: PASS (all groups, including the existing ones).

- [ ] **Step 5: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/lib/src/connection/value_objects/write_payload_limit.dart bluey/test/connection/value_objects/write_payload_limit_test.dart
git commit -m "fix(connection): clamp WritePayloadLimit to the 512-octet attribute cap (I343)"
```

---

## Task 2: Integration test through `maxWritePayload`

Confirms the clamp actually bites on the full `Connection.maxWritePayload` path (platform reports > 512 → consumer sees 512), so it can't regress if the funnel changes.

**Files:**
- Test: `bluey/test/connection/max_write_payload_test.dart`

- [ ] **Step 1: Write the failing test**

Add this test inside the existing `group('Connection.maxWritePayload', () { ... })` (after the `'falls back to MTU-3 when no override set'` test, before that group's closing `});`):

```dart
    test('clamps an over-512 platform report to 512 (I343)', () async {
      // iOS reports MTU-3 = 514 for withoutResponse at MTU 517; the consumer
      // must see the spec-capped 512 or large writes corrupt on Android.
      fakePlatform.setMaxWriteLengthOverride(
        TestDeviceIds.device1,
        withResponse: 514,
        withoutResponse: 514,
      );
      final connection = await bluey.connect(deviceFor(TestDeviceIds.device1));

      final wnr = await connection.maxWritePayload(withResponse: false);
      final wr = await connection.maxWritePayload(withResponse: true);

      expect(wnr.value, equals(512));
      expect(wr.value, equals(512));
    });
```

- [ ] **Step 2: Run, verify it fails**

Run: `cd bluey && flutter test test/connection/max_write_payload_test.dart`
Expected: FAIL — without the Task 1 clamp this would be `514`; with Task 1 already committed it PASSES. (If Task 1 is in place, this test should pass immediately — it's a regression guard at the integration layer. Run it to confirm green; if it errors on `setMaxWriteLengthOverride` signature, match the existing calls in this file which already use `withResponse:`/`withoutResponse:`.)

- [ ] **Step 3: Run the full connection suite to confirm no regression**

Run: `cd bluey && flutter test test/connection/`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/test/connection/max_write_payload_test.dart
git commit -m "test(connection): integration guard for the 512 write-payload clamp (I343)"
```

---

## Task 3: Docs, backlog status, cleanup, full verify

**Files:**
- Modify: `bluey/docs/cross-platform-quirks.md`
- Modify: `docs/backlog/I343-ios-to-android-multi-chunk-writenoresponse-loses-2-bytes-per-frame.md`

- [ ] **Step 1: Add a cross-platform-quirks note**

Append a short section to `bluey/docs/cross-platform-quirks.md` (match the file's existing `##`-section style):

```markdown
## Single writes are capped at 512 bytes regardless of MTU

The Bluetooth spec caps an attribute value at **512 octets** (Core Spec Vol 3,
Part F §3.2.9), independent of the negotiated ATT MTU. So even at MTU 517 (where
`MTU - 3` = 514), the largest single `connection.write(...)` payload that
reliably arrives is **512**. iOS's CoreBluetooth over-reports the
write-without-response maximum as `MTU - 3`; spec-conforming peripherals (e.g.
Android) silently truncate the overflow, and a Write Command gives no error.
bluey hides this: `connection.maxWritePayload(...)` is already clamped to 512,
so sizing chunked writes from it is safe on both platforms. (See backlog I343.)
```

- [ ] **Step 2: Flip I343 to fixed**

In `docs/backlog/I343-ios-to-android-multi-chunk-writenoresponse-loses-2-bytes-per-frame.md` frontmatter: set `status: open` → `status: fixed`, add `fixed_in: <this branch's clamp commit SHA>` after the `status:` line, set `last_verified: 2026-06-03`. Add one line to the top status block: "Fixed by clamping `WritePayloadLimit.fromPlatform` to the 512-octet attribute cap (`min(MTU-3, 512)`); see `docs/superpowers/specs/2026-06-03-write-payload-512-cap-design.md`." (Get the SHA: `git rev-parse --short HEAD` after Task 1.)

- [ ] **Step 3: Full Dart suite + analyze (all packages)**

```bash
cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test && flutter analyze
cd ../bluey_platform_interface && flutter test && flutter analyze
cd ../bluey_android && flutter test && flutter analyze
cd ../bluey_ios && flutter test && flutter analyze
```
Expected: all green, analyze clean. (Pure Dart domain change; native untouched.)

- [ ] **Step 4: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/docs/cross-platform-quirks.md docs/backlog/I343-ios-to-android-multi-chunk-writenoresponse-loses-2-bytes-per-frame.md
git commit -m "docs(I343): note the 512-octet write cap; mark fixed"
```

- [ ] **Step 5: Delete the throwaway bisect branch**

The `-2` verification hack + native logging are no longer needed (the real fix is the 512 clamp).

```bash
cd /Users/joel/git/neutrinographics/bluey
git branch -D i343-bisect-instrumentation
```

---

## Optional (recommended) on-device confirmation

The `-2` hack already proved 512-sized writes arrive intact and gossip flows. The real fix yields the same 512 at MTU 517, so this is belt-and-suspenders, not a gate: rebuild gossip against this branch, reconnect, trigger a large sync, and confirm iOS→Android chats flow with zero `Malformed gossip` on Android. (This is exactly what the deferred **I344** stress test will automate.)

---

## Self-Review

**Spec coverage:** clamp in `fromPlatform` → Task 1; `maxAttributeValueLength = 512` const + spec citation → Task 1; both write types (the override sets both; the integration test asserts both) → Task 2; sentinels preserved → Task 1; docs → Task 3 Step 1; I343 fixed → Task 3 Step 2; bisect-branch cleanup → Task 3 Step 5; I344 as on-device guard → noted. No native changes (intentional, per spec). ✅

**Placeholder scan:** every code step has complete code; commands have expected output; no TBD/"handle edge cases". ✅

**Type consistency:** `maxAttributeValueLength` (int const), `WritePayloadLimit.fromPlatform(int) -> WritePayloadLimit`, `.value` (int), `connection.maxWritePayload({required bool withResponse}) -> WritePayloadLimit`, `fakePlatform.setMaxWriteLengthOverride(id, withResponse:, withoutResponse:)` — all match the real signatures read from the code/tests. ✅
