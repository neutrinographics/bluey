# Shared DeviceStreams Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `DeviceStreams` exists once, in a library of `bluey_platform_interface` that only platform packages import, and Android's disconnect-echo rule is a small filter in `bluey_android` in front of it.

**Architecture:** The class moves, minus its echo rule, to `bluey_platform_interface/lib/src/implementation/` and is exported by a second public library, `platform_implementation.dart`, which the main library never exports. `bluey_android` gains `DisconnectEcho`, a filter that knows nothing of streams; its connection manager asks it before it passes a state report on. A new guard rule keeps `bluey` from naming the implementation library.

**Tech Stack:** Dart 3.7, Flutter 3.47.x (the cloud gates' version), `flutter_test`, `mocktail` (the managers' tests), `bluey_guards`.

**Spec:** Joel's ruling 2 of 2026-11-26, in `/mnt/project-files/bluey-slice1-2026-11-18/architecture-review.md` ("Rulings"), confirmed with two additions in `architecture-review-fable.md` ("The three rulings"). The behaviour being kept is rulings 34 and 35 of `/mnt/project-files/bluey-slice1-2026-11-18/build-ledger/progress.md`. The short design below is the rest of the spec.

## Design

**Why.** `bluey_android/lib/src/device_streams.dart` and `bluey_ios/lib/src/device_streams.dart` are the same 116 lines, with the same test file. The iOS copy carries a rule that is a fact about Android: the Android plugin echoes every disconnect request as a `disconnecting` report, even one it then fails (backlog I397).

**What changes.**

| Unit | Where | What it is for |
| --- | --- | --- |
| `DeviceStreams` | `bluey_platform_interface/lib/src/implementation/device_streams.dart` | Each device's state and notification streams, and which link a late signal belongs to. No echo rule. |
| `platform_implementation.dart` | `bluey_platform_interface/lib/` | The library a platform package imports for code platform packages share. Exports `DeviceStreams` only. |
| `DisconnectEcho` | `bluey_android/lib/src/disconnect_echo.dart` | Knows which `disconnecting` report is the echo of a local disconnect request. |
| `ReservedLibraryRule` | `bluey_guards/lib/src/architecture/rules/reserved_library_rule.dart` | Flags a file that names a library reserved for other packages. |

**Approaches considered.**

1. *A filter that is asked* (chosen). `DisconnectEcho` has two methods and names only `PlatformConnectionState`. The Android manager tells it a disconnect was asked and asks it whether a report is the echo. It does not know `DeviceStreams` exists, so each is tested alone.
2. *A filter that wraps `DeviceStreams`.* The manager would call the wrapper for `disconnect` and `reportState` and the shared class for the other five operations, so one object would be reached two ways. Rejected: more coupling for two fewer lines in the manager.
3. *A flag or hook on the shared class.* Ruled out by ruling 2.

**Behaviour.** Nothing an app sees changes. On Android the echo is dropped exactly as today: the mark is set when the disconnect is asked, before the host is called; the next `disconnecting` report for that device is dropped; a `disconnected` report clears the mark. The check runs before the report reaches `DeviceStreams`, as `_isEcho` runs first today, so the owed-last-report rules never see an echo. On iOS the echo rule goes. No Swift source sends `disconnecting` (checked by search of `bluey_ios/ios`), so no report was ever dropped there.

**Calls Claude made (overrule any).**

- The library is named `platform_implementation.dart`, imported as `package:bluey_platform_interface/platform_implementation.dart`.
- The Fable review's guard is built now: `bluey` may not name that library anywhere, infrastructure and the composition root included. The existing `framework placement` rule already covers the other layers. The example app has no architecture tests and is not held.
- No package version changes: every package is `publish_to: none` and resolves by path, and no app-visible behaviour changes. Each of the three CHANGELOGs gets one line.
- The Android manager is on the size list at 409 lines and may not grow. The wiring adds six lines, so its three one-expression mappers (`_mapService`, `_mapCharacteristic`, `_mapDescriptor`) become expression bodies, which removes six.

## Design review (cohesion, coupling, DDD, Clean Architecture)

- **`DeviceStreams`**: one responsibility, the lifetime of a device's two streams and the link each late signal belongs to. Depends on `PlatformConnectionState` and `PlatformNotification` of its own package (checked against `platform_interface.dart`), inward only. Layer: platform interface, implementation support. It is not domain code; its language is the platform interface's (device, link, report).
- **`platform_implementation.dart`**: exports one file of its own package. `bluey_platform_interface.dart` does not export it, held by a test in Task 1. Dependents: `bluey_android`, `bluey_ios`. `bluey` is refused by the guard in Task 4.
- **`DisconnectEcho`**: one responsibility, one Android fact. Depends on `PlatformConnectionState` only. Layer: platform implementation (`bluey_android`). `AndroidConnectionManager` depends on it and on `DeviceStreams`; neither depends on the other or on the manager (checked against `android_connection_manager.dart` lines 78, 129 to 142 and 344 to 346).
- **`ReservedLibraryRule`**: a pure function of a `SourceTree`, as every rule is (checked against `ArchitectureRule` and `FrameworkRule`). It names no package of Bluey; the library is configuration `bluey_architecture.dart` passes in.
- **Bounded contexts**: none is touched. No file under `bluey/lib` changes.
- **Finding, fixed here**: `bluey/test/fakes/fake_platform.dart` says in two doc comments that it drops the echo "as the platform packages' `DeviceStreams` do". After this change that is Android's filter. Task 3 corrects the wording; the fake's behaviour does not change.

Verdict: ready.

## Global Constraints

- TDD: no production code without a failing test first. Tests use `// arrange`, `// act`, `// assert`, and real objects or the existing mocks, never a new mock of `DeviceStreams`.
- Comments say why, never how. No inline comments, no journal comments.
- No list in any `known_violations.dart` grows and no count rises.
- No file under `bluey/lib`, no native file and no Pigeon file changes. `bluey/api/bluey.api` does not change.
- Commit messages are Conventional Commits and end with the session's attribution lines.
- Gates before the pull request, from the repository root unless a folder is named: `flutter analyze`; `flutter test` in `bluey_platform_interface`, `bluey_android`, `bluey_ios` and `bluey`; `dart test` in `bluey_guards`; the format check of `CLAUDE.md`; `dart run test/architecture/list_growth.dart origin/main test/architecture/known_violations.dart` in each package that has one (`bluey` also passes `test/known_defects/roster.dart`); `dart run bluey_guards:public_api lib/bluey.dart api/bluey.api` in `bluey`.

## Review Focus

- A `disconnecting` report with no disconnect asked, on Android: delivered (Task 2, filter test 3).
- A second disconnect request before the first echo arrives, on Android: one mark, one echo dropped, as today's set gives (Task 2, filter test 5).
- An echo that arrives after the host failed the disconnect, on Android: dropped, and the next `disconnecting` delivered (Task 2, manager test).
- A `disconnecting` report after a disconnect request on iOS: delivered, since iOS has no echo (Task 3, manager test).
- A `disconnecting` report after `DeviceStreams.disconnect` in the shared class: delivered, since the rule left it (Task 1).

---

### Task 1: `DeviceStreams` in the platform interface

**Files:**
- Create: `bluey_platform_interface/lib/src/implementation/device_streams.dart`
- Create: `bluey_platform_interface/lib/platform_implementation.dart`
- Create: `bluey_platform_interface/test/implementation/device_streams_test.dart`
- Create: `bluey_platform_interface/test/platform_implementation_library_test.dart`
- Modify: `bluey_platform_interface/CHANGELOG.md`

**Interfaces:**
- Produces: `package:bluey_platform_interface/platform_implementation.dart`, exporting `DeviceStreams` with today's public members unchanged: `bool open(String)`, `Future<void> close(String)`, `Future<void> disconnect(String, Future<void> Function())`, `statesOf`, `notificationsOf`, `reportState`, `reportNotification`.

- [ ] **Step 1: Write the failing tests.** Copy `bluey_android/test/device_streams_test.dart` to the new test path. Import `package:bluey_platform_interface/platform_implementation.dart` in place of the Android import. Delete the whole group `the platform's echo of a disconnect request` and add in its place:

```dart
group('a disconnecting report', () {
  test('a disconnecting report after a disconnect request is delivered, '
      'since an echo is the platform package\'s to drop', () async {
    // arrange
    streams.open('dev');
    final answer = Completer<void>();
    final states = expectLater(
      streams.statesOf('dev'),
      emitsInOrder([
        PlatformConnectionState.disconnecting,
        PlatformConnectionState.disconnected,
        emitsDone,
      ]),
    );

    // act
    final closing = streams.disconnect('dev', () => answer.future);
    streams.reportState('dev', PlatformConnectionState.disconnecting);
    streams.reportState('dev', PlatformConnectionState.disconnected);

    // assert
    await states;
    answer.complete();
    await closing;
  });
});
```

In `platform_implementation_library_test.dart`, one test, `the main library does not export the implementation library`: read `lib/bluey_platform_interface.dart` and expect its text to contain neither `src/implementation/` nor `platform_implementation.dart`.

- [ ] **Step 2: Run them and see them fail.** `cd bluey_platform_interface && flutter test test/implementation test/platform_implementation_library_test.dart`. Expected: the first fails to compile (no such library); the second passes already, which is right for a rule that holds from the start.

- [ ] **Step 3: Move the class.** Copy `bluey_android/lib/src/device_streams.dart` to the new path. Import `../platform_interface.dart` in place of the package import. Remove `_echoExpected`, `_isEcho`, the first line of `reportState` and the `_echoExpected.add` line of `disconnect`, and the last paragraph of `disconnect`'s doc comment (the one that begins "The next `disconnecting` report is not delivered"). Add one sentence to the class doc: a platform whose plugin reports something that is not about a link (Android's echo of a disconnect request) drops it before it reports here. Create `platform_implementation.dart` with a library doc comment saying it is for platform packages, never for an app or for `bluey`, and `export 'src/implementation/device_streams.dart';`.

- [ ] **Step 4: Run the package's suite.** `cd bluey_platform_interface && flutter test`. Expected: all pass, the architecture tests included.

- [ ] **Step 5: CHANGELOG and commit.** Under a new `## Unreleased` heading at the top of `bluey_platform_interface/CHANGELOG.md`: "New library `platform_implementation.dart` for code platform packages share; it holds `DeviceStreams`. Not for apps." Commit: `refactor(platform-interface): hold DeviceStreams once, in a library for platform packages`.

### Task 2: Android's filter, and Android on the shared class

**Files:**
- Create: `bluey_android/lib/src/disconnect_echo.dart`
- Create: `bluey_android/test/disconnect_echo_test.dart`
- Modify: `bluey_android/lib/src/android_connection_manager.dart`
- Modify: `bluey_android/test/android_connection_manager_test.dart`
- Delete: `bluey_android/lib/src/device_streams.dart`, `bluey_android/test/device_streams_test.dart`
- Modify: `bluey_android/test/architecture/known_violations.dart` (only if the manager ends below 409 lines), `bluey_android/CHANGELOG.md`

**Interfaces:**
- Consumes: `DeviceStreams` from Task 1.
- Produces:

```dart
/// (doc: why Android needs it, I397, and that the app already knows it asked)
class DisconnectEcho {
  /// Records that a disconnect of [deviceId] was asked, so its echo is recognised.
  void expectFor(String deviceId);

  /// Whether [state] is the echo of a disconnect asked of [deviceId]. An echo
  /// is recognised once; a `disconnected` report means none is coming.
  bool isEcho(String deviceId, PlatformConnectionState state);
}
```

- [ ] **Step 1: Write the filter's failing tests** in `disconnect_echo_test.dart`, one group `the echo of a disconnect request`:
  1. `the disconnecting report after a request is the echo`: `expectFor('dev')`; `isEcho('dev', disconnecting)` is true.
  2. `an echo is recognised once`: after test 1's two calls, a second `isEcho('dev', disconnecting)` is false.
  3. `a disconnecting report with no request is not an echo`: `isEcho('dev', disconnecting)` is false.
  4. `a disconnected report means no echo is coming`: `expectFor('dev')`; `isEcho('dev', disconnected)` is false; then `isEcho('dev', disconnecting)` is false.
  5. `two requests before the echo expect one echo`: `expectFor('dev')` twice; `isEcho` is true, then false.
  6. `a request for one device expects no echo from another`: `expectFor('a')`; `isEcho('b', disconnecting)` is false; `isEcho('a', disconnecting)` is true.
  7. `connecting and connected reports are never the echo and leave it expected`: `expectFor('dev')`; `isEcho('dev', connecting)` and `isEcho('dev', connected)` are false; `isEcho('dev', disconnecting)` is true.

- [ ] **Step 2: Run and see them fail.** `cd bluey_android && flutter test test/disconnect_echo_test.dart`. Expected: does not compile.

- [ ] **Step 3: Implement `DisconnectEcho`** over one `Set<String>`, with the logic of today's `_isEcho`. Run the file again. Expected: 7 pass.

- [ ] **Step 4: Write the manager's failing tests** in `android_connection_manager_test.dart`, in a new group `the plugin's echo of a disconnect request`, using the file's existing `mockHostApi` and its way of reporting a state (`onConnectionStateChanged` with a `ConnectionStateEventDto`):
  1. `the echo of a disconnect request does not reach the device's listeners`: connect `dev`; listen to `connectionStateStream('dev')`; hold the host's `disconnect` on a `Completer`; call `disconnect('dev')`; report `disconnecting`, then `disconnected`; expect the stream to emit `[disconnected]` and end; complete the answer.
  2. `the echo of a disconnect the host fails does not reach the listeners, and the link's own disconnecting report does`: connect; the host's `disconnect` throws `PlatformException(code: 'x')`; `disconnect('dev')` throws; report `disconnecting`, `disconnecting`, `disconnected`; expect `[disconnecting, disconnected]` and the end.

- [ ] **Step 5: Run and see them fail.** Delete `bluey_android/lib/src/device_streams.dart` and its test first, and import `package:bluey_platform_interface/platform_implementation.dart` in the manager, so the manager runs on the shared class. `flutter test test/android_connection_manager_test.dart`. Expected: the two new tests fail (the echo is delivered); every other test passes.

- [ ] **Step 6: Wire the filter.** In the manager: a field `final DisconnectEcho _disconnectEcho = DisconnectEcho();`; `disconnect` calls `_disconnectEcho.expectFor(deviceId)` before `_streams.disconnect(...)`; `onConnectionStateChanged` maps the state, returns when `_disconnectEcho.isEcho(event.deviceId, state)`, and reports it otherwise. Update the class doc to name both collaborators. Turn `_mapService`, `_mapCharacteristic` and `_mapDescriptor` into expression bodies.

- [ ] **Step 7: Run the package's suite and count.** `cd bluey_android && flutter test && wc -l lib/src/android_connection_manager.dart`. Expected: all pass and at most 409 lines. When the count is lower, rewrite the manager's entry in `known_violations.dart` with it and run `flutter test test/architecture` again.

- [ ] **Step 8: CHANGELOG and commit.** `## Unreleased` in `bluey_android/CHANGELOG.md`: "Internal: `DeviceStreams` now comes from `bluey_platform_interface`; the disconnect echo is dropped by `DisconnectEcho`. No behaviour change." Commit: `refactor(android): drop the disconnect echo in a filter in front of the shared DeviceStreams`.

### Task 3: iOS on the shared class, and the documents

**Files:**
- Modify: `bluey_ios/lib/src/ios_connection_manager.dart`, `bluey_ios/test/ios_connection_manager_test.dart`, `bluey_ios/CHANGELOG.md`
- Delete: `bluey_ios/lib/src/device_streams.dart`, `bluey_ios/test/device_streams_test.dart`
- Modify: `bluey/test/fakes/fake_platform.dart` (two doc comments, near lines 560 and 569), `bluey/test/fakes/fake_device_streams_test.dart` (its doc comment)
- Modify: `docs/ARCHITECTURE.md` (line 232 and the package table near line 20), `docs/backlog/I397-emit-android-disconnecting-only-after-gatt-disconnect-succeeds.md`, `docs/backlog/I369-adapter-controller-leaks.md`

**Interfaces:**
- Consumes: `DeviceStreams` from Task 1.

- [ ] **Step 1: Write the failing test** in `ios_connection_manager_test.dart`, `a disconnecting report after a disconnect request is delivered, since iOS has no echo to drop`: connect `device-1` with the file's existing mocks; listen; hold the host's `disconnect` on a `Completer`; call `disconnect`; report `disconnecting`, then `disconnected`; expect `[disconnecting, disconnected]` and the end; complete the answer.

- [ ] **Step 2: Run and see it fail.** `cd bluey_ios && flutter test test/ios_connection_manager_test.dart`. Expected: the new test fails with `[disconnected]`.

- [ ] **Step 3: Switch iOS.** Delete the iOS copy and its test; import the implementation library in the manager. Run `flutter test` in `bluey_ios`. Expected: all pass; the manager's line count is unchanged (one import replaced by one).

- [ ] **Step 4: Correct the documents.**
  - `fake_platform.dart`: the comment near line 560 says "as the platform interface's `DeviceStreams` does"; the one near 569 says the fake drops the echo "as `bluey_android`'s `DisconnectEcho` does". `fake_device_streams_test.dart`: "the platform interface's `DeviceStreams`".
  - `docs/ARCHITECTURE.md` line 232: "`DeviceStreams`, in `bluey_platform_interface`'s library for platform packages (`platform_implementation.dart`), keeps ...". The package table: add to the `bluey_platform_interface` row that it also holds `platform_implementation.dart`, code the platform packages share, which no app and nothing in `bluey` imports.
  - I397: the filter is `DisconnectEcho` (`bluey_android/lib/src/disconnect_echo.dart`); once the plugin's emit moves, that class and its two call sites can go.
  - I369: one sentence appended to its "Fixed in" paragraph: the class has since moved to `bluey_platform_interface`, held once.

- [ ] **Step 5: Run `bluey`'s suite.** `cd bluey && flutter test`. Expected: all pass (only comments changed there).

- [ ] **Step 6: CHANGELOG and commit.** `## Unreleased` in `bluey_ios/CHANGELOG.md`: "Internal: `DeviceStreams` now comes from `bluey_platform_interface`, without Android's disconnect-echo rule, which iOS never needed. No behaviour change." Commit: `refactor(ios): use the shared DeviceStreams, without Android's echo rule`.

### Task 4: `bluey` may not name the implementation library

**Files:**
- Create: `bluey_guards/lib/src/architecture/rules/reserved_library_rule.dart`
- Create: `bluey_guards/test/architecture/rules/reserved_library_rule_test.dart`
- Modify: `bluey_guards/lib/architecture.dart` (one export, in alphabetical place)
- Modify: `bluey/test/architecture/bluey_architecture.dart`, `bluey/test/architecture/known_violations.dart`
- Modify: `docs/ARCHITECTURE.md` (the rule table of section 4 and the lists table of section 5)

**Interfaces:**
- Produces:

```dart
/// (doc: why a library is reserved, and that the rule judges every Dart file of the tree)
final class ReservedLibraryRule implements ArchitectureRule {
  const ReservedLibraryRule({required this.libraries});

  /// The libraries, by the exact URI a file names them with, that no file of
  /// the package may name.
  final Set<String> libraries;

  @override
  String get name => 'reserved libraries';
}
```

A violation is `Violation(source.path, uri)` for each URI of a Dart source (`source.uris`, which covers imports and exports) that is in `libraries`.

- [ ] **Step 1: Write the failing tests**, in the style of `framework_rule_test.dart` (`tree`, `naming`, `entries` from `../support/trees.dart`), with `_reserved = 'package:bluey_platform_interface/platform_implementation.dart'`:
  1. `a file that names a reserved library is a violation wherever it sits`: files at `lib/bluey.dart` (an `export`), `lib/src/api/bluey.dart`, `lib/src/features/connection/infrastructure/adapters/platform_links.dart` and `lib/src/connection/a.dart` each name it; expect four entries, `'<path> -> $_reserved'`, in the tree's order.
  2. `the package's other libraries are not reserved`: a file naming `package:bluey_platform_interface/bluey_platform_interface.dart` and `dart:async`; expect none.
  3. `a library whose name only begins the same way is not reserved`: a file naming `package:bluey_platform_interface/platform_implementation_extras.dart`; expect none.

- [ ] **Step 2: Run and see them fail.** `cd bluey_guards && dart test test/architecture/rules/reserved_library_rule_test.dart`. Expected: does not compile.

- [ ] **Step 3: Implement the rule and export it.** Run `dart test` in `bluey_guards`. Expected: all pass, its own size and public-exports rules included.

- [ ] **Step 4: Hold `bluey` to it.** In `blueyRules`, after `'publicExports'`: `'reservedLibraries': const ReservedLibraryRule(libraries: {'package:bluey_platform_interface/platform_implementation.dart'})`. In `known_violations.dart`, after `publicExports`: a doc comment "The files that name a library reserved for the platform packages." and `const reservedLibraries = <String>[];`.

- [ ] **Step 5: See the rule bite, then pass.** Add `import 'package:bluey_platform_interface/platform_implementation.dart';` to `bluey/lib/src/bluey.dart`, run `cd bluey && flutter test test/architecture`, and expect `reserved libraries` to fail naming that file. Remove the import, run again, and expect every rule to pass. Then `dart run test/architecture/list_growth.dart origin/main test/architecture/known_violations.dart test/known_defects/roster.dart`. Expected: no list grew.

- [ ] **Step 6: Document the rule.** Section 4's table gains a row after `public exports`: `reserved libraries`, "A Dart file of the package that names `package:bluey_platform_interface/platform_implementation.dart`, the library the platform packages share code through. Infrastructure and the composition root are held too", configured by "`libraries` in `bluey_architecture.dart`". Section 5's `bluey` row lists `reservedLibraries` among the empty lists.

- [ ] **Step 7: Run every gate of Global Constraints, then commit.** Commit: `test(guards): bluey may not name the platform packages' implementation library`.

### Task 5: The pull request

- [ ] **Step 1:** Push `claude/project-thread-nmuds7` and open the pull request against `main`, titled `refactor: one DeviceStreams for both platforms, Android's echo as a filter`. Its body opens with the project's two attribution lines, then says: what moved, that no app-visible behaviour changed, the calls listed under "Calls Claude made", and under "Not verified here" that the Kotlin and XCTest suites run in CI only and that no native file changed.
- [ ] **Step 2:** Assign `da1nerd`, request their review, and subscribe to the pull request's activity.
