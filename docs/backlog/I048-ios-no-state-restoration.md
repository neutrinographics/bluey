---
id: I048
title: iOS managers initialized without restore identifier; state restoration disabled
category: limitation
severity: medium
platform: ios
status: open
last_verified: 2026-04-26
---

## Symptom

When the iOS app is force-killed (by the user or by iOS itself under memory pressure) while serving as a peripheral or holding central connections, the app cannot be relaunched in the background to process subsequent BLE events. The `CBCentralManager` and `CBPeripheralManager` instances are not registered with iOS's state preservation system, so the OS doesn't track them across launches.

For consumers building apps that need long-running BLE in the background (continuous monitoring, beacon-style proximity, multi-day connections), this is a hard ceiling: the connection lifecycle ends when the app process ends, regardless of `UIBackgroundModes` declarations.

## Location

- `bluey_ios/ios/Classes/CentralManagerImpl.swift:57` — `centralManager = CBCentralManager(delegate: nil, queue: nil)`.
- `bluey_ios/ios/Classes/PeripheralManagerImpl.swift:37` — `peripheralManager = CBPeripheralManager(delegate: nil, queue: nil)`.

## Root cause

`CBManagerOptionRestoreIdentifierKey` is the iOS API for opting in to state preservation/restoration. Without it, the managers are created fresh on each launch and have no relationship to any prior session.

Setting the restore identifier alone is not sufficient — the host app's `AppDelegate` must also implement `application(_:didFinishLaunchingWithOptions:)` to **synchronously** re-instantiate the manager with the same identifier before the Flutter engine plugin registrant runs, and the plugin's `centralManager(_:willRestoreState:)` delegate method must reattach delegates and re-acquire peripherals from the restored-state dictionary.

## Notes

Implementation requires Flutter-plugin-level changes that touch the host app's `AppDelegate` and Info.plist. Mirror what `flutter_blue_plus` does:

- Plugin-level: accept a configuration option `restoreState: bool` and a `restoreIdentifier: String?` (default-derived).
- Host app: declare `bluetooth-central` and/or `bluetooth-peripheral` in `UIBackgroundModes`, and in `AppDelegate.swift` ensure the manager is re-instantiated synchronously in `application(_:didFinishLaunchingWithOptions:)` *before* `GeneratedPluginRegistrant.register(with:)`.
- Implement `centralManager(_:willRestoreState:)` and `peripheralManager(_:willRestoreState:)` to reattach delegates and rebuild the `peripherals: [String: CBPeripheral]` dict from `CBCentralManagerRestoredStatePeripheralsKey`.

This is non-trivial but it is the difference between "iOS background BLE works" and "iOS background BLE works only as long as the user doesn't force-quit the app."

**Force-quit caveat:** state restoration does NOT survive user-initiated force-quit (swipe up in app switcher). This is by Apple design. Document this loudly in the final integration guide.

External references:
- Apple, [Performing Long-Term Actions in the Background](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetoothLE/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html).
- Apple, [`CBCentralManagerOptionRestoreIdentifierKey`](https://developer.apple.com/documentation/corebluetooth/cbcentralmanageroptionrestoreidentifierkey).
- Apple, [`centralManager(_:willRestoreState:)`](https://developer.apple.com/documentation/corebluetooth/cbcentralmanagerdelegate/centralmanager(_:willrestorestate:)).
- [`flutter_blue_plus`](https://github.com/chipweinberger/flutter_blue_plus) reference implementation — search for `restoreState` and the Info.plist key `flutter_blue_plus_restore_state`.
