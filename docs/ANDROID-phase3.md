# Phase 3 — Android Companion (M3, Foreground Service)

Status: implemented and validated on-device (TECNO LH6n, Android 14,
API 34). The phone link (UDP discovery, `tDeviceStatus` broadcasts,
desktop→phone clipboard) now keeps working while the app is backgrounded
or the screen is off, via an Android foreground service. The USB-unplug
Wi-Fi-only soak passed; the optional WhatsApp paste test is the only
outstanding item (see bottom).

## What was added

### Native (Kotlin)
- **`BoonForegroundService.kt`** — new foreground service:
  - notification channel `boon_link` (`IMPORTANCE_LOW`), notification
    "Boon / Boon link aktif", id `4545`, icon `stat_notify_sync`, taps
    open `MainActivity`;
  - `ACTION_START` / `ACTION_STOP` intents driven from Dart;
  - `startForeground(..., FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)`
    with the type passed at runtime — Android 14 requires it when
    `FOREGROUND_SERVICE_CONNECTED_DEVICE` is declared; verified live:
    `types=00000010`, `isForeground=true`, no fallback needed
    (targetSdk 36);
  - `START_STICKY`; everything inside try/catch so a notification crash
    degrades to "no service" instead of killing the app.
- **`MainActivity.kt`** — new `boon/service` method channel:
  - `start` → `startForegroundService(...)`,
  - `stop` → `stopService(...)`,
  - `requestNotificationPermission` (API 33+, request code 4545).
- **`AndroidManifest.xml`** — added `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `POST_NOTIFICATIONS`, and the
  `<service android:name=".BoonForegroundService" android:exported="false"
  android:foregroundServiceType="connectedDevice"/>` declaration.

### Dart
- `lib/services/companion/foreground_service.dart` —
  `start` / `stop` / `ensureNotificationPermission`, no-op off Android.
- `lib/core/state/app_state.dart`:
  - persisted `keepLinkAlive` setting (default **on**, file
    `keepalive.txt` in the app support dir);
  - FGS started in `init()` after `acquireMulticast()` and before
    `LinkService.start()`;
  - `setKeepLinkAlive` toggles the service live;
  - `syncNow({bool quiet})` — one manual status push (+ desktop
    clipboard pull), `clipboard.markApplied(...)` so the returned text
    is not immediately re-sent back as an outgoing change;
  - `pushSelfStatus()` — public wrapper around `_broadcastSelfStatus()`.
- `lib/app/phone_shell.dart` — `WidgetsBindingObserver`; on a real
  resume-from-background (previous state `paused`/`hidden`; first-launch
  resume fires before focus and Android denies the clipboard read, so it
  is gated) calls `syncNow(quiet: true)` + `pushSelfStatus()`.
- `lib/features/settings/settings_page.dart` — Android-only
  "Background Link" card with the toggle and a plain explanation that
  the persistent notification is an Android rule.

## Verified on device
- FGS start granted with the app foregrounded
  (`allowStartForeground=PROC_STATE_TOP`, notification posted).
  `adb`-launch with the screen off/locked was denied (Android 14
  background-FGS-start restriction) — environmental, not app logic.
- **3+ minute screen-off/background soak**: desktop device card kept a
  fresh Last Seen with live battery updates while the phone screen was
  off; status was Connected again immediately on wake.
- **Desktop→phone clipboard across background**: paste from the desktop
  landed on the phone ("Copied From Desktop — 22 chars") while the phone
  app was on the HOME screen (phone→desktop validated in the opposite
  direction previously).
- **Toggle off→on** (Settings → Background Link): OFF stops the service
  (`dumpsys` shows no ServiceRecord, notification gone); ON restarts it
  as foreground with `connectedDevice` type; Link stays functional.
- **Resume sync push-back**: returning the app to the foreground bumped
  the desktop's Last Seen within seconds (12.21 → 12.24) — the
  lifecycle observer fires on a real resume.

## Known gaps / honest limitations
- **Swipe-away kills the Flutter engine** even with the FGS process
  alive — the link stops until the app is re-opened (Android trims
  activities; keeping the engine alive is a future milestone, e.g. via
  `stopWithTask=false` or moving the link to the service process).
- **Background clipboard reads** are blocked on Android 10+ whenever
  the app has no focus; reads happen only on resume / while foregrounded
  (already a documented Android rule; write direction works from the
  background because the app owns the connection).
- **Trust store wipe observed once** (mystery, not reproduced): the
  phone's `trusted_devices.json` was found reset to `{}` mid-session;
  restored manually via `run-as` + base64. No M3 code path writes that
  file except explicit pairing/forget; root cause still unknown.
- **Discovery advertisement interface**: the desktop advertises the
  address of whichever interface the kernel routes broadcast through
  (USB-tether subnet `10.86.40.x` while the phone Wi-Fi was off, Wi-Fi
  `192.168.1.6` otherwise). Devices on both subnets co-exist via
  pair-by-address.
- The desktop app can go stale after a network change on this Linux box
  (poller stops; `SocketException: Connection reset` on the old port is
  logged unhandled) — restarting the desktop app re-binds. Out of M3
  scope (desktop hardening).

## USB-unplug soak (passed)
- USB cable unplugged, phone screen left off, ~5 minutes.
- The route change killed the desktop's UDP socket (it was bound to the
  USB interface's broadcast address; `Network is unreachable` on 45021)
  and the desktop app went stale — its TCP listener stays bound but the
  app needed a restart, after which the phone reconnects immediately
  over Wi-Fi alone.
- Verified entirely on Wi-Fi (USB still out): stable TCP
  `192.168.1.9 → 192.168.1.2:45022` for 4+ minutes with the screen off,
  secure session auto-restored from the trust store (no re-pairing),
  device card Connected with live battery and fresh Last Seen.
- Conclusion: the FGS keeps the phone side alive through the unplug;
  the desktop's own staleness after an interface loss is pre-existing
  desktop hardening work (out of M3 scope).

## Remaining user-run check
- WhatsApp paste test on the phone (paste-from-desktop in a real app
  input field) — skipped, low risk: the same pipeline was already
  verified via `am broadcast` landing in the app UI while backgrounded.

## Commands
```bash
flutter build apk --debug
~/Android/Sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell "dumpsys activity services com.example.boon | grep isForeground"
flutter run -d linux        # desktop side
flutter test                # still green
flutter analyze             # clean
```
