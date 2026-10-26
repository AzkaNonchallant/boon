# Transparent floating window (Windows)

Boon behaves like a floating desktop widget: one unified light dashboard
panel (nav rail fused into it) floats over the Windows desktop, and the
wallpaper is visible around it.

## How it works (native, in the runner)

The transparency is applied to the native Win32 window in
`windows/runner/win32_window.cpp` (`ApplyWidgetWindowChrome`, called right
after the window is created) — it does not depend on any window plugin:

1. **Frameless**: `WS_CAPTION` is stripped (title bar gone), `WS_THICKFRAME`
   kept, and `WM_NCCALCSIZE` returns 0 so the client area covers the entire
   window (no non-client frame is painted).
2. **Transparent**: `DwmExtendFrameIntoClientArea(-1)` + `DwmEnableBlurBehindWindow`
   put the DWM in alpha-composite mode over the glass frame, and the
   `SetWindowCompositionAttribute` accent policy
   (`ACCENT_ENABLE_TRANSPARENTGRADIENT`, gradient color `0x00000000`) removes
   the opaque white/black window backing. This is the standard technique for
   transparent overlay windows; changing Flutter colors alone cannot do this.
3. **Widget behaviors**: the window is created `HWND_TOPMOST` (always on top
   by default) at 1640x990; `windows/runner/flutter_window.cpp` exposes a
   `boon/window` MethodChannel with `startDragging` (native title-bar drag),
   `setAlwaysOnTop`, `minimize`, `close`.
4. Flutter side: `theme.dart` uses `scaffoldBackgroundColor: Colors.transparent`
   and the shell scaffold in `home_shell.dart` paints nothing outside the
   sidebar + main panel. The old dark navy `_DesktopBackground` painter and the
   fixed 1180px centered layout were removed — the panels fill the window, so
   there is no dark surround and no dead space.

`lib/app/window.dart` (`BoonWindow`) talks to the `boon/window` channel.
Settings > "Widget Window" toggles always-on-top at runtime.

## Notes / limitations

- A `flutter_acrylic`/`window_manager`-based approach was tried first but did
  not fully apply on the target machine; the native runner path replaced it
  and both packages were removed.
- The widget has a fixed size (no manual edge-resizing while frameless);
  it supports move (drag anywhere on the shell), minimize and close.
- First launch on a new Windows network: Windows Firewall may ask for LAN
  permission — allow it, or discovery (UDP 45021) and the link server
  (TCP 45022) cannot accept inbound connections.
