# Boon — Personal Device Bridge

Boon adalah aplikasi Flutter local-first untuk menghubungkan desktop Windows,
Android, iPad/iOS, dan perangkat lain secara langsung di jaringan lokal. Tidak
ada cloud server atau VPS yang dibutuhkan.

## Status implementasi

### Sudah tersedia

- Dashboard desktop bergaya soft/neumorphism sesuai referensi di `ui/`.
- Sidebar navigation: Home, Clipboard, File Transfer, Phone Buddy, Settings.
- Empty state nyata ketika belum ada perangkat terhubung.
- Demo Mode opsional untuk mengevaluasi dashboard tanpa ponsel Android.
- Device discovery UDP dan koneksi peer-to-peer TCP.
- Pairing dengan kode verifikasi dan trusted-device store.
- Pesan aplikasi terenkripsi untuk clipboard, status device, notifikasi, media,
  link, dan text.
- File transfer terenkripsi dengan progress, cancel, dan SHA-256 verification.
- Android punya tab Files untuk memilih file, melihat history sent/received,
  membuka file, dan menyimpan foto/video ke Gallery atau auto-save.
- Windows frameless/always-on-top widget window melalui native runner.
- Android companion untuk battery, Notification Listener, MediaSession, dan
  foreground link service.
- iPad/iOS dapat pair langsung dengan Android atau perangkat Boon lain di LAN;
  desktop tidak perlu menjadi server.
- Phone Buddy punya pause forwarding dan filter aplikasi notifikasi per app.

### Batasan yang disengaja

- Clipboard Android background dibatasi oleh OS; sinkronisasi foreground/manual
  tetap diperlukan pada kondisi tertentu.
- iPad/iOS perlu tetap membuka Boon agar koneksi LAN aktif. Sinkron clipboard
  dari iPad dilakukan manual supaya Boon tidak memicu izin pasteboard berulang.
- Media control hanya aktif bila Android memiliki media session aktif.
- Notification mirroring membutuhkan izin Notification Access di Android.
- Boon Island drag-and-drop penuh masih menjadi fase berikutnya.

## Struktur utama

```text
lib/
├── app/              # shell, theme, page routing, native window bridge
├── core/
│   ├── models/       # device, media, notification, transfer, activity
│   ├── networking/   # discovery, transport, pairing, sessions
│   ├── protocol/     # message types and wire format
│   ├── security/     # identity, crypto, trusted devices
│   └── state/        # shared AppState
├── features/         # dashboard, clipboard, drop, phone buddy, settings
├── services/         # clipboard, companion, transfer, demo link
└── shared/           # reusable neumorphic widgets and utilities
android/              # Kotlin companion integrations
windows/              # frameless native desktop window
docs/                 # architecture and platform notes
test/                 # networking tests
```

## Menjalankan

Pastikan Flutter `3.47+` dan Dart `3.13+` tersedia.

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Di Linux, target yang tersedia:

```bash
flutter run -d linux
flutter build linux --release
```

Windows membutuhkan Visual Studio dengan workload **Desktop development with
C++**. Build Windows tidak dapat divalidasi dari environment Linux ini.

## Mode demo

Buka **Settings → Demo Mode** untuk menampilkan Pixel 8 virtual. Data demo
dipisahkan dari koneksi real dan tidak memberi akses jaringan atau mengirim file
sungguhan.

Untuk pairing perangkat nyata, buka **Settings → Pair by IP** atau tunggu
perangkat trusted ditemukan melalui discovery lokal.

## Dokumentasi

- `docs/ARCHITECTURE-phase1.md` — status fondasi dan arsitektur jaringan.
- `docs/ANDROID-phase2.md` sampai `ANDROID-phase4.md` — integrasi Android dan
  batasan clipboard/companion.
- `docs/transparent-window.md` — catatan native window Windows.
