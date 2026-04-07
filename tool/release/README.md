# LocalDrop Release Tooling

This folder contains repo-owned release helpers so native artifacts can be built
without IDE-only steps or committed secrets.

## Android signing

Release signing is driven by either:

- `android/key.properties`
- environment variables

Supported environment variables:

- `LOCALDROP_KEYSTORE_PATH`
- `LOCALDROP_KEYSTORE_PASSWORD`
- `LOCALDROP_KEY_ALIAS`
- `LOCALDROP_KEY_PASSWORD`

Use [android/key.properties.example](/e:/Projects/Flutter/Tiko/local_drop/android/key.properties.example) as the template for local signing setup.

## Commands

- Windows desktop ZIP: `pwsh -File tool/release/build_windows_release.ps1`
- Android APK + AAB: `pwsh -File tool/release/build_android_release.ps1`
- Linux tarball/AppImage scaffold: `bash tool/release/build_linux_release.sh`
- macOS zip/DMG scaffold: `bash tool/release/build_macos_release.sh`

## Optional version overrides

These scripts accept the same Flutter version overrides:

- `LOCALDROP_BUILD_NAME`
- `LOCALDROP_BUILD_NUMBER`

## Desktop signing hooks

Optional environment variables are intentionally externalized and never stored in
the repo.

- Windows: `LOCALDROP_WINDOWS_SIGN_COMMAND`
- macOS: `LOCALDROP_MACOS_CODESIGN_IDENTITY`, `LOCALDROP_MACOS_NOTARY_PROFILE`
