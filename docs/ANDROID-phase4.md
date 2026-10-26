# Phase 4 — Phone Buddy (Notifications + Media Control)

Status: implemented; `flutter analyze`, `flutter test` and
`flutter build apk --debug` pass. On-device validation checklist at the
bottom (TECNO LH6n, Android 14) — results are filled in after the device
run.

## What was added

### Native (Kotlin)
- **`BoonNotificationListener.kt`** — new `NotificationListenerService`:
  - mirrors other apps' notifications as
    `{kind: notification, appId, appName, title, body, time}`;
    own package, ongoing notifications and group summaries are skipped;
    identical `(key, title, body)` reposts are de-duplicated (last 80);
  - watches the active `MediaSession` through `MediaSessionManager`
    (same Notification Access grant), emitting
    `{kind: media, available, playing, title, artist, album, positionMs,
    durationMs}` on metadata/playback changes and preferring the session
    that is actually playing;
  - static `applyMediaAction(play|pause|prev|next)` drives the active
    `MediaController.transportControls` from the desktop's buttons;
  - `eventSink` feeds the Flutter `EventChannel`; events are dropped
    while no engine is listening.
- **`MainActivity.kt`** — new `boon/companion` channel
  (`isListening`, `openListenerSettings`, `requestRebind`,
  `applyMediaAction`) and the `boon/companion/events` EventChannel.
  `isListening` checks the live service first, then parses
  `Settings.Secure.enabled_notification_listeners` (repo-owned component
  only).
- **`AndroidManifest.xml`** — declares
  `.BoonNotificationListener` with
  `android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"`
  and the `NotificationListenerService` intent filter. No new dangerous
  runtime permission: the user grants Notification Access through the
  system Special Access screen.

### Dart
- `lib/services/companion/companion_bridge.dart` — typed no-op-off-
  Android wrapper: `events` stream, `isListening`, `openListenerSettings`,
  `requestRebind`, `applyMediaAction`.
- `lib/core/networking/link_service.dart` — `broadcastApp(type, payload)`
  fans an encrypted app message out to every paired session.
- `lib/core/state/app_state.dart`:
  - subscribes to the native event stream on Android;
  - `_mirrorNotification` → encrypted `tNotification` broadcast (paused
    when "Allow Notification" is off);
  - `_mirrorMedia` → encrypted `tMediaState` broadcast; re-sent when a
    peer (re)connects so the desktop does not show a stale track;
  - `tMediaAction` inbound case → `CompanionBridge.applyMediaAction`, so
    the desktop's play/pause/prev/next reaches the real session;
  - `tCompanionAction` (new message type) → the phone opens the
    Notification Access screen when the desktop asks;
  - `notificationListenerActive` + `companionSupported` state,
    `refreshCompanionStatus()` (called on resume), and the phone's status
    broadcast now carries `notificationListener: true|false`;
  - `DeviceStatusData.notificationsReady` stores the remote phone's
    capability so the desktop UI can be honest about mirroring.
- `lib/core/protocol/boon_message.dart` — `tCompanionAction`.

### UI
- **Phone — `LinkStatusPage`**: permission card while Notification
  Access is missing ("Allow access" → system screen), explaining that the
  same grant powers media control.
- **Desktop — Phone Buddy**: the Notification card shows whether the
  phone granted access and offers "Enable on phone", which sends
  `tCompanionAction: open_notification_settings` (the phone opens its own
  settings — the desktop cannot grant it).
- **Desktop — dashboard**: notification icon mapping understands Android
  package ids, and the empty state explains when phone access is off.

## How the flow works now

1. User grants Notification Access on the phone (Boon Link page or via
   the desktop's "Enable on phone").
2. The system binds `BoonNotificationListener`; it emits to the
   EventChannel inside the running Flutter engine.
3. `AppState` encrypts and broadcasts `tNotification` / `tMediaState` to
   paired peers over the existing TCP link (no new port, no server).
4. The desktop reuses its existing handlers: notifications land in the
   dashboard feed (body stripped when Privacy Mode is on) and media lands
   in the player card.
5. Play/pause/prev/next travel back as `tMediaAction` and are applied to
   the phone's real `MediaSession`.

## Privacy
- Nothing is stored permanently on the phone: notifications are forwarded
  immediately and never written to disk.
- Desktop history is capped at 12 entries, in memory only.
- Privacy Mode strips the notification body on the desktop; the phone
  still forwards the full payload (user picked "all notifications,
  censor on desktop").
- "Allow Notification" off pauses forwarding at the phone, so nothing
  leaves the device.

## Known limitations (honest)
- **Engine lifetime**: mirroring needs the Flutter engine alive. The
  foreground service keeps the process up while backgrounded, but
  swipe-away still kills the engine (pre-existing Phase 3 gap) — the
  listener keeps running but events are dropped until Boon is reopened.
- **Notification filtering** skips ongoing notifications (downloads, FGS,
  media players) and group summaries on purpose. After an app sends its first
  notification, it appears in Android Settings → Notification Apps and can be
  disabled per app. New apps default to enabled so the user can discover them.
- **Media progress** is event-based: the position is a snapshot, not a
  live tick, so the desktop's progress bar does not animate by itself.
- **Media control** requires an active session; apps that expose no
  `MediaSession` cannot be controlled and the button is a no-op
  (reported once in the activity feed).
- Notification titles/bodies come from `EXTRA_TITLE` /
  `EXTRA_TEXT` / `EXTRA_BIG_TEXT`; some apps use custom remote views and
  may mirror a blank body.
- Notification Access is a sensitive grant: intentionally no
  Accessibility-Service workaround is used anywhere.

## Validation checklist (on-device)
```bash
flutter analyze
flutter test
flutter build apk --debug
~/Android/Sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-debug.apk
flutter run -d linux
```
- [ ] Phone → Link → "Allow access" opens Android Notification Access;
      Boon appears in the list and the card disappears after granting.
- [ ] Desktop Phone Buddy shows "Phone access granted" (status broadcast).
- [ ] Send a WhatsApp/Telegram message → appears on the desktop dashboard
      with the correct app name and time; privacy mode hides the text.
- [ ] Toggle "Allow Notification" off → new phone notifications stop.
- [ ] Play media (Spotify/YouTube Music) on the phone → title/artist
      appear on the desktop; play/pause/prev/next from the desktop act on
      the phone.
- [ ] Screen off / phone on home screen → notifications and media still
      arrive (foreground service alive).
- [ ] Desktop "Enable on phone" when access is off → the phone opens the
      Notification Access screen.
