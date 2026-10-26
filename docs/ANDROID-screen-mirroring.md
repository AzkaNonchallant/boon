# Android screen mirror (Wi-Fi, no ADB)

The first screen-control slice uses Android MediaProjection and Boon's existing
encrypted connection to a paired device. It is a low-rate preview (up to about
3 JPEG frames/second at 720 px wide), not a smooth video stream.

## Setup

1. Pair the Android phone and desktop in Boon and connect them to the same LAN.
2. On the phone, open **Settings → Remote screen control → Open settings** and
   enable Boon's Accessibility service if remote taps are wanted. This is a
   sensitive, explicit Android permission; Boon cannot enable it itself.
3. Keep Boon open on the phone. From desktop **Phone Buddy**, choose **View
   screen**, then approve Android's screen-capture prompt on the phone.
4. Tap the mirrored image to send taps. Closing the viewer stops capture.

Android displays its own foreground sharing notification while capture runs.
The capture permission is requested by Android and must be approved by the
phone user. Only an authenticated paired peer receives frames.

## Current limits

- Touch taps are supported; keyboard input, drag/swipe gestures, audio, and
  high-frame-rate video are not implemented yet.
- Sharing must be initiated while Boon is open on the phone so Android can
  show its consent UI. OEM background-activity rules may prevent a desktop
  request from opening that prompt while Boon is backgrounded.
- Frames currently travel as encrypted JPEG messages over the app JSON link.
  This is suitable only for a prototype preview; a dedicated media transport
  (for example WebRTC) is needed before claiming smooth or efficient mirroring.
- Accessibility control availability is checked from the live service and may
  take a status refresh after changing the Android setting.

The Android APK builds, but this flow still needs validation on physical
Android devices and across OEM versions before it should be treated as stable.
