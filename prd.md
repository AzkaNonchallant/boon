# BOON — Personal Device Bridge
## Project Specification & Implementation Prompt

You are an experienced software engineer and UI/UX developer. Help me build **Boon**, a personal device ecosystem that connects computers, Android phones, and eventually iPads or other devices.

I have provided a UI/UX reference image for the Boon desktop dashboard. Use it as the primary visual reference. Implement the application as a real, functional desktop application, not just a static mockup.

Do not redesign the interface without a good reason. Preserve the overall layout, visual identity, spacing, and component hierarchy shown in the reference.

---

# 1. Project Overview

Boon is a local-first personal device bridge.

Its purpose is to make multiple personal devices work together seamlessly without requiring a cloud account or a VPS.

Users should be able to:

- Synchronize clipboard content between devices.
- Transfer files between devices.
- View phone status from the desktop.
- Receive phone notifications on the desktop.
- Control phone media playback.
- Send text and links between devices.
- Interact with connected devices through a floating desktop widget called **Boon Island**.
- Connect multiple devices directly, without requiring the laptop to act as a central server.

The main goal is to create an experience similar to a unified personal device ecosystem.

## Product principles

1. Local-first communication.
2. Privacy by design.
3. Fast and simple interactions.
4. Multi-device architecture.
5. Modular and maintainable code.
6. Native integrations where necessary.
7. Honest handling of operating-system limitations.

---

# 2. Technology Stack

Use the following stack unless there is a strong technical reason to propose an alternative.

### Core application

- Flutter
- Dart
- Flutter Desktop for Windows
- Flutter Android
- Kotlin for Android-specific functionality

### Desktop target

Windows is the primary desktop platform for the MVP.

The architecture should allow future support for:

- Linux
- macOS

### Android target

Android is the primary mobile platform for the MVP.

iPadOS support is a future expansion. Do not assume that Android APIs are available on iPadOS.

### Networking

Use a local-network communication architecture.

Potential technologies:

- WebSocket for control messages and device events.
- Encrypted connections for communication.
- HTTP or a suitable encrypted transfer channel for file transfers.
- Local device discovery using mDNS/Bonjour or another suitable mechanism.
- QR code or verification-code-based pairing.

Choose suitable libraries after evaluating their compatibility with Flutter Desktop and Android.

Do not add a cloud server or VPS dependency.

---

# 3. UI/UX Reference

The provided image represents the intended Boon desktop dashboard.

The visual direction is:

- Clean and futuristic.
- Soft UI / neumorphism.
- Light gray interface panels.
- Dark navy desktop background.
- Blue accent colors.
- Rounded cards and buttons.
- Soft shadows and subtle depth.
- Minimalist icons.
- Clear visual hierarchy.
- Spacious layout.

The UI should feel like a native desktop product, not a generic web dashboard.

## Main layout

The desktop dashboard contains:

### A. Left Sidebar

A vertical navigation sidebar containing:

- Home
- Clipboard
- File Transfer
- Phone Buddy
- Settings

The sidebar should:

- Remain visible on the main dashboard.
- Highlight the currently selected page.
- Use icon-based navigation.
- Preserve the visual style of the reference.
- Support a responsive layout when the application window is resized.

### B. Header

The header contains:

- Greeting text, such as "GOOD MORNING".
- Notification button.
- User/profile or application settings button.

The greeting should be dynamic based on the current time.

### C. Connected Device Card

The device card displays:

- Device name, for example Pixel 8.
- Connection status.
- Last-seen time.
- Battery percentage.
- Charging status.
- Connection type when available.

The card must use real device data when a device is connected.

If no device is connected, show an appropriate empty state.

### D. Feature Cards

The dashboard includes three main feature cards:

1. Clipboard
2. File Transfer
3. Phone Buddy

Each card should be clickable and navigate to its corresponding page.

### E. Recent Activity

Display recent Boon activity, such as:

- Files received.
- Files sent.
- Clipboard synchronization events.
- Device connection events.
- Transfer completion or failure.

Activity data should come from the application state or local storage.

Do not use permanent clipboard-content history by default.

### F. Notifications

Display recent notifications received from connected devices.

Notification information should include:

- Application icon or identifier.
- Application name.
- Notification title.
- Notification content, subject to privacy settings.
- Time received.

Only show notifications when the user has granted the required permission.

### G. Media Player

Display:

- Album artwork when available.
- Song title.
- Artist.
- Playback progress.
- Previous button.
- Play/pause button.
- Next button.

Media controls must communicate with an actual supported media session on the connected Android device.

Do not make the controls appear functional if no media session is available.

### H. Quick Actions

The dashboard contains quick actions such as:

- Send Link.
- Send Text.

The actions should allow the user to select a connected device and send content to it.

---

# 4. Main Features

## Feature A — Boon Link

Boon Link manages device discovery, pairing, and connections.

Required functionality:

- Discover available Boon devices on the local network.
- Pair devices using QR codes or verification codes.
- Maintain a list of trusted devices.
- Display online/offline status.
- Reconnect when possible.
- Allow the user to forget or revoke a trusted device.
- Handle network changes and connection failures.

Devices must authenticate before exchanging data.

Do not allow an unknown device to access clipboard content or transfer files without authorization.

## Feature B — Boon Clip

Boon Clip provides universal clipboard functionality.

Required functionality:

- Synchronize text between supported devices.
- Update the desktop system clipboard.
- Allow users to paste synchronized text using Ctrl+V.
- Support automatic synchronization where the operating system allows it.
- Prevent duplicate events.
- Prevent synchronization loops.
- Allow synchronization to be paused or resumed.
- Provide clear synchronization status.

Important Android limitation:

Android restricts background clipboard access, especially on newer Android versions.

Do not assume that a foreground service or an ordinary background process can detect every clipboard change.

Investigate and validate the appropriate Android implementation before promising fully automatic clipboard synchronization.

An optional custom IME may be evaluated, but it must not be treated as a guaranteed solution.

Do not use Accessibility Services as a workaround for clipboard restrictions.

If automatic synchronization cannot be supported in a particular condition, provide a clear fallback and document the limitation.

## Feature C — Boon Drop

Boon Drop handles file transfers.

Required functionality:

- Transfer files between connected devices.
- Support Android-to-Windows transfers.
- Support Windows-to-Android transfers.
- Allow multiple connected devices.
- Let the user select the destination device.
- Display file name and size.
- Display transfer progress.
- Support cancellation.
- Handle duplicate file names.
- Verify file integrity.
- Display completed, failed, or cancelled status.
- Store transfer metadata locally.

The file transfer system must work without cloud storage.

## Feature D — Boon Phone Buddy

Phone Buddy is the desktop companion interface for connected phones.

Required functionality:

### Device status

- Battery percentage.
- Charging status.
- Connection status.
- Last-seen time.

### Notifications

- Receive Android notifications through Notification Listener permission.
- Allow users to select which applications can forward notifications.
- Support pause and mute.
- Respect privacy settings.
- Avoid exposing notification content when privacy mode is enabled.

### Media control

- Play/pause.
- Previous.
- Next.
- Display current media information when available.

### Quick actions

- Send text to a phone.
- Send a link to a phone.
- Open a received link when supported.
- Display the result of the requested action.

Do not claim that Boon provides full remote control of the phone.

---

# 5. Boon Island — Floating Desktop Interface

Boon Island is a floating desktop widget inspired by the interaction concept of Dynamic Island.

It should be integrated into Boon Desktop.

It is not a separate application.

Its purpose is to provide quick access to Boon functionality without opening the full dashboard.

## Island states

### Idle

A small floating pill displaying:

- Boon icon.
- Connection indicator.
- Optional battery indicator.

### Drag-and-drop

When the user drags files over the Island:

- Expand the Island.
- Display a drop target.
- Show "Drop to send".
- Allow selection of the destination device.

### File transfer

Display:

- File name.
- Destination device.
- Transfer progress.
- Cancel action.

### Completed

Display a success indicator and return to the idle state.

### Phone Companion

The Island should also provide quick access to:

- Phone battery.
- Notifications.
- Media controls.
- Quick actions.
- Connected device selection.

The Island should be configurable:

- Always on top.
- Hide or show.
- Position on screen.
- Open the main Boon dashboard.
- Select a default destination device.

The Windows implementation must be validated for:

- Borderless floating window behavior.
- Always-on-top behavior.
- Native drag-and-drop support from Windows File Explorer.
- Window positioning.
- Focus and interaction behavior.

Do not assume that Flutter alone provides all of these capabilities without native integration.

---

# 6. Multi-Device Architecture

Boon must support more than two devices.

Example:

- Android phone.
- iPad.
- Windows desktop.

The devices should be able to communicate directly with one another when supported.

Examples:

- Android ↔ iPad.
- Android ↔ Windows.
- iPad ↔ Windows.

The laptop must not be required to act as a central server for all transfers.

For the MVP, prioritize devices on the same local network.

However, the architecture should not hardcode the assumption that all communication must pass through Windows.

Use a peer-to-peer-oriented design.

Each device should have:

- A unique device ID.
- A device name.
- A device type.
- A supported-capabilities list.
- A trusted-device identity.
- A connection state.

The application should distinguish between:

- Device discovery.
- Pairing.
- Authentication.
- Connection.
- Data transfer.

Future remote connectivity may be added later, but it must not be required for the MVP.

---

# 7. Security and Privacy

Security is a core requirement.

Implement:

- Device authentication.
- Encrypted communication.
- Trusted-device management.
- Explicit permission handling.
- Ability to revoke a device.
- Clipboard synchronization controls.
- Notification privacy controls.
- Secure handling of file transfers.

Do not:

- Store clipboard content permanently by default.
- Log clipboard content.
- Log notification content unnecessarily.
- Allow unknown devices to access data.
- Expose an unauthenticated transfer server to the local network.

Use secure pairing and key management appropriate for the selected implementation.

---

# 8. Suggested Project Structure

Use a modular architecture.

Example:

```text
boon/
├── lib/
│   ├── app/
│   ├── core/
│   │   ├── networking/
│   │   ├── protocol/
│   │   ├── security/
│   │   ├── storage/
│   │   └── diagnostics/
│   ├── services/
│   │   ├── pairing/
│   │   ├── clipboard/
│   │   ├── transfer/
│   │   └── companion/
│   ├── features/
│   │   ├── home/
│   │   ├── clipboard/
│   │   ├── drop/
│   │   ├── phone_buddy/
│   │   ├── devices/
│   │   └── settings/
│   └── main.dart
├── android/
├── windows/
├── test/
├── docs/
└── pubspec.yaml
```

This structure is a starting point.

Adjust it if necessary, but keep the code modular and maintainable.

---

# 9. Implementation Strategy

Do not implement every feature at once.

Use incremental development.

### Phase 1 — Desktop Foundation

- Set up Flutter Desktop for Windows.
- Create the application structure.
- Implement the dashboard UI based on the reference image.
- Implement navigation.
- Create reusable components.
- Implement responsive desktop layout.

At this stage, use mock data only where real device integration is not available.

Clearly separate mock data from real services.

### Phase 2 — Android Feasibility

- Set up Flutter Android.
- Implement native Kotlin integration.
- Validate clipboard behavior.
- Validate battery and device status.
- Validate notification access.
- Validate media controls.

Investigate platform limitations early.

### Phase 3 — Device Connectivity

- Implement device discovery.
- Implement pairing.
- Implement authentication.
- Implement local networking.
- Implement connection status.
- Implement reconnection behavior.

### Phase 4 — Clipboard

- Implement desktop clipboard integration.
- Implement Android clipboard integration.
- Implement synchronization.
- Implement deduplication.
- Implement privacy controls.

### Phase 5 — File Transfer

- Implement two-way file transfer.
- Implement destination selection.
- Implement progress and cancellation.
- Implement file integrity checks.
- Implement transfer history.

### Phase 6 — Phone Buddy

- Implement device status.
- Implement notification mirroring.
- Implement media controls.
- Implement quick actions.

### Phase 7 — Boon Island

- Implement floating window.
- Implement drag-and-drop.
- Implement file transfer progress.
- Implement Phone Buddy interactions.
- Implement Island settings.

### Phase 8 — Stabilization

- Test connection failures.
- Test multiple devices.
- Test large file transfers.
- Test permissions.
- Test privacy controls.
- Build a Windows installer.
- Prepare documentation.

---

# 10. Development Rules

Follow these rules throughout the implementation:

1. Do not replace the provided UI design with a generic dashboard.
2. Do not remove existing features without asking.
3. Do not create unnecessary abstractions.
4. Do not implement fake functionality and present it as real.
5. Keep mock data clearly separated from production services.
6. Do not introduce a cloud or VPS dependency.
7. Do not assume all devices have identical capabilities.
8. Do not assume Android and iPadOS have identical APIs.
9. Explain technical limitations clearly.
10. Keep the application buildable after each phase.
11. Prefer small, incremental changes.
12. Reuse existing project structure and code whenever possible.

Before modifying existing code:

- Inspect the project structure.
- Identify the current implementation.
- Understand the existing dependencies.
- Explain the proposed changes.
- Preserve existing working functionality.

---

# 11. Immediate Task

Start with **Phase 1 — Desktop Foundation**.

First:

1. Inspect the existing project, if one is available.
2. Confirm the current Flutter and Dart setup.
3. Identify the target Windows configuration.
4. Propose the folder structure.
5. Implement the dashboard UI based on the provided reference image.
6. Implement sidebar navigation.
7. Create reusable UI components.
8. Use mock data only for device information that is not yet connected to real services.
9. Ensure the application builds and runs on Windows.

Do not implement all networking and Android functionality in the first step.

The immediate objective is to create a clean, functional Boon Desktop foundation that closely follows the supplied UI/UX design.

After completing the first phase, explain:

- What was implemented.
- Which files were created or modified.
- How to run the application.
- What remains for the next phase.

The final product should feel like a cohesive personal device ecosystem, not a collection of unrelated utilities.
