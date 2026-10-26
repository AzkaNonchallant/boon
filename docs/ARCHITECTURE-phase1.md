# Boon — Phase 1 report (Desktop Foundation + Networking)

## Yang sudah jadi

### 1. Desktop UI (mengikuti ui/*.png tanpa redesign)
- **Shell** (lib/app/home_shell.dart): background navy + glow, sidebar pill
  melayang (Home, Clipboard, File Transfer, Phone Buddy, Settings),
  header dengan greeting dinamis (GOOD MORNING/AFTERNOON/EVENING),
  tombol notifikasi & profil, panel utama terpisah.
- **Dashboard** (features/home/dashboard_page.dart): kartu device
  (status/last seen nyata saat peer terhubung), 3 feature cards, Recent
  Activity, Notification, media player, 2 quick actions (Send Link/Text).
- **Clipboard** (features/clipboard/clipboard_page.dart): AUTOSYNC toggle,
  Sync Direction (CAD | P→D | D→P), Sensitive Content, Last Sync.
- **File Transfer** (features/drop/drop_page.dart): segmented Send/History,
  dropzone drag & drop (desktop_drop) + Select Files (file_selector),
  history dengan progress/cancel.
- **Phone Buddy** (features/phone_buddy/phone_buddy_page.dart): status
  device (baterai/charging/last seen), notification + privacy mode,
  media controls, quick actions.
- **Settings** (features/settings/settings_page.dart): identitas device,
  demo mode, trusted devices (forget), pair-by-IP, status discovery.
- Komponen reusable: lib/shared/widgets/ (NeuCard, NeuButton,
  NeuIconButton, NeuToggle, NeuRadioRow, AppIconCircle, PhoneSilhouette,
  MediaPlayerCard, QuickActionDialog).

### 2. Networking (NYATA, bukan mock)
- **Discovery** (core/networking/discovery/discovery_service.dart):
  UDP broadcast tiap 2 detik pada port 45021, pruning peer stale.
- **Transport** (core/networking/transport/peer_connection.dart):
  TCP + framing JSON per newline, port 45022.
- **Link/protocol** (core/networking/link_service.dart,
  core/protocol/boon_message.dart): greeting identity, pairing state
  machine, sesi terautentikasi, kirim pesan aplikasi (clipboard, status,
  media, notifikasi, quick link/text), auto-reconnect untuk trusted
  devices via discovery.
- **Security** (core/security/): pairing kode verifikasi 6 digit,
  tukar half-secret kedua sisi, session key SHA-256, semua pesan data
  AES-256-GCM. Trusted store persist di app-support dir.
- **File transfer engine** (services/transfer/transfer_service.dart):
  request/accept + chunked base64 via kanal terautentikasi, sender completion
  setelah receiver SHA-256 verification, cancel, penamaan duplikat, dan
  metadata history lokal di app-support.
- **Android file experience**: tab Files, Android document picker, membuka file
  melalui FileProvider, dan MediaStore Gallery untuk foto/video.
- **Clipboard sync** (services/clipboard/clipboard_service.dart):
  polling 1.2s desktop, dedup + loop-prevention.
- **Test** (test/link_service_test.dart): dua node sungguhan saling
  pairing dan tukar clipboard terenkripsi — LULUS, rerun-stabil.

## Pemisahan mock vs real
- `MockLinkService` (services/mock/) hanya aktif lewat **Demo Mode**
  (default OFF agar koneksi nyata tidak pernah tertutup oleh data demo; aktifkan
  di Settings untuk evaluasi UI). Semua layar tanpa peer menampilkan empty
  state asli.

## Cara menjalankan
- Windows: `flutter run -d windows`
- Linux (di mesin ini): `flutter run -d linux` / `flutter build linux --release`
- Uji jaringan antar 2 instansi: jalankan app di 2 machine / 2 user
  (atau ubah port di Settings–pair by IP), lalu pairing via dialog kode.
- Verifikasi cepat: `flutter analyze`, `flutter test`,
  `flutter build linux --release`

## Diketahui & batasan (jujur)
- Pairing MVP memakai code derived dari nonce+id — melindungi dari
  salah pairing; MITM-resist penuh (QR key) menyusul.
- Clipboard Android (background restriction) belum — native Kotlin
  di Phase 2/4.
- Notifikasi & media control butuh NotificationListener/MediaSession
  di Android (Phase 2/6). UI media hanya aktif saat peer mengirim
  media state.
- File transfer receiver otomatis menerima request dari trusted device;
  konfirmasi per file di UI menyusul.
- Boon Island (floating window) — Phase 7.

## Langkah berikutnya (Phase 2)
- Kode native Kotlin: battery/charging (BatteryManager), Notification
  Listener Service, MediaSession callbacks, foreground service, mDNS/
  broadcast permission, clipboard foreground strategy.
- Rusting komunikasi Android ↔ Windows memakai stack LinkService ini.
