# LocalDrop

LocalDrop is a cross-platform nearby sharing app built with Flutter for fast, direct transfers over the local network.

It is designed for people who want a clean, modern way to send files, folders, photos, videos, text, and clipboard content between devices without using a cloud relay.

## What LocalDrop Does

- Discovers nearby devices on the same local network
- Sends content directly device-to-device
- Requires receiver approval for every incoming transfer
- Keeps transfer history on the device
- Stores received files in the folder you choose
- Opens the received folder from the app where the platform supports it

## Features

- Cross-platform support:
  - Android
  - iPhone / iPad
  - Windows
  - macOS
  - Linux
- Nearby discovery with:
  - UDP LAN discovery as the universal baseline
  - Android NSD as an additive native source
  - Apple Bonjour as an additive native source
- Transfer types:
  - Files
  - Photos
  - Videos
  - Folders
  - Text notes
  - Clipboard text
- Explicit `Accept` / `Decline` approval flow
- Transfer progress, diagnostics, and history
- In-app folder view plus native folder open where supported
- System gallery and file pickers on mobile
- Desktop drag-and-drop where supported by the current platform build
- Light and dark themes
- English localization
- Foreground-only nearby model on mobile

## Product Highlights

- No cloud relay
- No account required
- Direct local-network transfer flow
- Receiver-controlled approvals
- HTTPS-only encrypted transfer transport on the local transfer port
- Peer certificate fingerprint pinning after the first successful transfer
- 6-12 digit receiver PIN protection
- Transfer history and transport logs are kept locally on the device

## Platform Support

| Platform | Status | Notes |
| --- | --- | --- |
| Android | Supported | Nearby discovery, sending, receiving, media pickers |
| iOS / iPadOS | Supported | Local Network access required, Files/share integration depends on iOS behavior |
| Windows | Supported | Nearby discovery, diagnostics, firewall integration |
| macOS | Supported | Nearby discovery, native Apple Bonjour support, user-selected file access |
| Linux | Supported | Nearby discovery and transfers on desktop environments |

## How It Works

1. Open LocalDrop on the devices you want to use.
2. Choose content on the sender.
3. Select a nearby device.
4. Enter the receiver PIN.
5. On first transfer, compare the short security codes shown on both devices.
6. Accept the request on the receiver.
7. LocalDrop transfers the content directly across the local network.

## Current App Sections

- `Nearby`
  - pick content
  - discover devices
  - start transfers
  - troubleshoot connection issues
- `History`
  - view completed and failed transfers
  - reopen received folders
- `Settings`
  - nickname
  - save directory
  - theme preference
  - trusted devices
  - identity / diagnostics details

## Privacy And Security

- LocalDrop is designed for direct local-network sharing
- Transfers are not routed through a LocalDrop cloud service
- Transfers use HTTPS on the local network; insecure HTTP transfer fallback is not used
- Each device has a local TLS certificate and certificate fingerprint
- The first encrypted transfer requires the user to compare short security codes in person
- After a successful encrypted transfer, the peer fingerprint is pinned as a trusted device
- If a known device ID later presents a different fingerprint, LocalDrop blocks sending and receiving until the old trust record is forgotten
- Receiver PINs must be numeric 6-12 digit values and are stored as PBKDF2-HMAC-SHA256 hashes with per-device salts
- Receiver approval is required before incoming transfer data is accepted
- Received folder archives are validated before extraction to block path traversal and oversized expansion
- Transfer checksums are verified before completion
- Preferences, transfer history, and transport logs are stored locally on the device
- See [PRIVACY_POLICY.md](PRIVACY_POLICY.md) for details about LocalDrop's privacy practices, data handling, and contact information

## Permissions And Capabilities

### Android

- `INTERNET`
- `ACCESS_NETWORK_STATE`
- `ACCESS_WIFI_STATE`
- `CHANGE_WIFI_MULTICAST_STATE`
- `NEARBY_WIFI_DEVICES` with `neverForLocation` for Android local Wi-Fi discovery APIs where required
- System file and media pickers for user-selected content

### iOS / iPadOS

- Local Network access
- Bonjour service advertisement / browsing
- Photo Library access for user-selected media
- Multicast entitlement for physical-device LAN discovery

### Windows

- Local network access
- Optional Windows firewall setup for inbound nearby discovery

### macOS / Linux

- Local network access
- User-selected file and folder access

## Project Structure

```text
lib/
  app/
  core/
  features/
    history/
    home/
    nearby/
    settings/
    transfers/
  l10n/
  models/
  services/
  state/
```

## Protocol Surface

LocalDrop currently uses these transfer routes:

- `GET /v1/transfer/health`
- `POST /v1/transfer/offer`
- `GET /v1/transfer/{id}/decision`
- `PUT /v1/transfer/{id}/data?itemId={itemId}`
- `POST /v1/transfer/{id}/complete`

The current protocol is `localdrop.secure.v5`. Peers that do not advertise HTTPS transfer support and a certificate fingerprint are treated as incompatible or a security failure instead of falling back to HTTP.

## Development

### Prerequisites

- Flutter `3.41.x`
- Dart `3.11.x`
- Android Studio for Android builds
- Xcode for iOS / macOS builds
- Visual Studio Build Tools for Windows builds
- GTK / CMake toolchain for Linux builds

### Common Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

### Build Commands

#### Android

```bash
flutter build apk --debug
flutter build appbundle --release
```

#### iOS

```bash
flutter build ios --release
```

Archive and upload with Xcode / Transporter.

#### Windows

```bash
flutter build windows --release
```

#### macOS

```bash
flutter build macos --release
```

#### Linux

```bash
flutter build linux --release
```

## License

This project is licensed under **GPL-3.0**.
See [LICENSE](LICENSE).
