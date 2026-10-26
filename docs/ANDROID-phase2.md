# Phase 2 — Android Companion (M1 + M2)

Status: foundation + native bridges implemented and building. Validated with
`flutter build apk --debug` and `flutter build linux --debug`; on-device run is
the remaining step (`flutter run -d <phone>` once USB debugging is enabled).

## What was added

### M1 — Foundation
- Android SDK licenses accepted; Flutter build JDK switched to Temurin 21
  (`~/.sdkman/candidates/java/21.0.11-tem`) because Fedora's
  `java-25-openjdk` is headless and ships no `javac`.
  Changed via `flutter config --jdk-dir=...`.
- `android/app/build.gradle.kts` — `minSdk = 24`, permissions in
  `AndroidManifest.xml` (label "Boon"):
  - `INTERNET` (TCP link on 45022),
  - `ACCESS_NETWORK_STATE`,
  - `CHANGE_WIFI_MULTICAST_STATE` (UDP discovery on 45021).
- `lib/core/security/device_identity.dart` — the Android branch of
  `supportDir()` now uses `path_provider` (`getApplicationSupportDirectory`)
  instead of the wrong `/data/local/tmp` fallback. Desktop paths unchanged.

### M2 — Native bridges
All native code lives in `android/app/src/main/kotlin/com/example/boon/MainActivity.kt`:

- **`boon/status`** — `start`/`stop` register/unregister a matched
  `ACTION_BATTERY_CHANGED` receiver pair (battery level + charging),
  `battery` returns the cached snapshot, `deviceName` returns
  `MANUFACTURER MODEL` so the Android identity is a real device name
  (wireless devices report `localhost` for hostname). Wired into
  `AppState._broadcastSelfStatus` so the `tDeviceStatus` broadcast every
  30s carries real battery/charging; the desktop device card shows them.
- **`boon/discovery`** — `acquire`/`release` around a
  `WifiManager.MulticastLock`. `AppState.init` acquires it *before*
  `LinkService.start()` binds the UDP discovery socket and releases it on
  dispose. If discovery binding still fails (firewall, AP isolation, APs
  that block broadcast 255.255.255.255), the existing errored path keeps
  the app usable and pair-by-address is shown in the phone UI.

### Phone UI
- `lib/app/phone_shell.dart` — phone-flavored shell (compact header +
  Link/Settings bottom nav) using `BoonColors`/neumorphic widgets.
  Incoming/outgoing pairing dialogs mirror `home_shell.dart`, resize down.
- `lib/features/link/link_status_page.dart` — device-Link screen showing
  own status with a real battery value, discovered peers (tap = outgoing
  pairing), pair-by-address fallback, trusted-device management.
- `lib/app/app.dart` picks `PhoneShell` on Android; desktop keeps
  `HomeShell` and runs unchanged.

## Verified on device (TECNO LH6n, USB + Wi-Fi LAN)
- MulticastLock acquired (`WifiService: acquireMulticastLock lockTag=boon-discovery`).
- Phone discovers the desktop ("fedora • verified") and auto-reconnects.
- Real `tDeviceStatus` flows both ways: desktop device card shows
  TECNO LH6n with real battery %, charging state and fresh Last Seen;
  the phone Link page header shows "Linked to your desktop".

## Bugs found and fixed during the first on-device run
1. **Auto-reconnect never restored the session key.** Only the inbound
   side loaded the stored `keyHex` from the trust store; the side that
   initiated the reconnect (the phone) kept `key == null`, so every
   encrypted frame was dropped silently on both ends while ping/pong
   kept the TCP session visibly "connected". Fix: `LinkService` restores
   the stored key from the trust store in the `hello` handler for
   outbound sessions too (lib/core/networking/link_service.dart).
2. **Demo data masked the live device.** The dashboard `primaryDevice`
   picked the mock Pixel 8 ahead of the real phone, and the PhoneShell
   header claimed "Linked to your desktop" because demo mode counted as
   an online peer. Fixes: real devices always win in `primaryDevice`,
   the phone header reads the real link state, and `demoMode` now
   defaults to **off** (still toggleable in Settings for UI-only runs).

## Honest Android limitations (Phase 2 scope)
- UDP discovery on phones is restricted by some APs (client isolation,
  no broadcast). Discovered lists can be empty there; pair manually via IP.
- `MulticastLock` keeps multicast receptive only while the app is
  foreground; background listening is beyond this phase (no foreground
  service yet).
- No notification listener / media control / clipboard auto-sync yet —
  Android 10+ background clipboard changes require separate validation,
  as already flagged in the project spec.

## Commands
```bash
flutter build apk --debug                          # phone app APK
~/Android/Sdk/platform-tools/adb devices           # confirm phone
flutter run -d <device-id>                         # run companion on the phone
flutter run -d linux                               # desktop side, same machine
```
Both nodes then see each other in their Discovered lists; pairing is the
verification-code flow in both directions. Tests: `flutter test` (pairing +
encrypted clipboard, still green).
