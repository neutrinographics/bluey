# Platform Interface: Replace `flutter/foundation` — Design Spec

## Goal

Remove the `flutter/foundation` dependency from `bluey_platform_interface` by replacing it with `package:meta` for `@immutable` and a private `_listEquals` helper for list equality. Mirrors the same change already applied to the `bluey` core package.

## Changes

### `bluey_platform_interface/pubspec.yaml`

Add `meta: ^1.11.0` under dependencies.

### `bluey_platform_interface/lib/src/platform_interface.dart`

- Replace `import 'package:flutter/foundation.dart'` with `import 'package:meta/meta.dart'`
- Add a private `_listEquals<T>()` helper function
- Replace 3 calls to `listEquals()` with `_listEquals()`:
  - `PlatformScanConfig.==` (1 call: `serviceUuids`)
  - `PlatformDevice.==` (2 calls: `serviceUuids` and `manufacturerData`)

### `bluey_platform_interface/lib/src/capabilities.dart`

- Replace `import 'package:flutter/foundation.dart'` with `import 'package:meta/meta.dart'`
- No other changes — only uses `@immutable`

## Impact

Zero behavior change. All existing tests pass. The platform interface types become independent of Flutter's foundation library.

## Out of Scope

- Structural reorganization of the platform interface package
- Changes to `bluey_android` or `bluey_ios`
- Test additions
