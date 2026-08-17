# SmoothRoute Native iOS MVP

The native recorder moves SmoothRoute's proven browser JSON model to Core Location and Core Motion so recording can continue with the screen locked or a navigation app visible.

## MVP capabilities

- SwiftUI interface for car, motorcycle, scooter, and the configured Road Glide profile
- best-for-navigation Core Location updates
- 10 Hz Core Motion device-motion capture
- iOS background location mode
- one-second atomic ride checkpoints
- append-only JSONL sample journal with explicit synchronization
- unfinished-ride detection and manual recovery
- browser-compatible JSON export through the iOS share sheet
- scene lifecycle and recovery markers
- no credentials or signing material in the repository

## Generate the Xcode project

The checked-in source uses XcodeGen so the Xcode project is reproducible:

```sh
cd ios
brew install xcodegen
xcodegen generate
open SmoothRoute.xcodeproj
```

The deployment target is iOS 17 and the bundle identifier is `com.smoothroute.rider`.

## Required capabilities

The generated app includes the `location` background mode and these privacy strings:

- Location When In Use
- Location Always and When In Use
- Motion Usage

The app requires **Always Location** before Start is enabled. The user starts recording while parked; the active background location session keeps the process eligible to receive Core Motion updates while the display is locked or a navigation app is foregrounded.

## First device validation

1. Start while parked with Location set to Always.
2. Record for 30 seconds foregrounded.
3. Lock for 60 seconds.
4. Unlock and verify GPS and motion counts advanced.
5. Start spoken navigation, return to SmoothRoute, then foreground navigation for 60 seconds.
6. Return and verify counts advanced without a browser-style gap.
7. Force-quit during a separate ride, reopen, resume, record 15 seconds, and export.
8. Inspect JSON for pre- and post-recovery samples.

Do not interact with the app while moving.

## Signing and TestFlight

Codemagic expects an App Store Connect integration named `smoothroute_app_store_connect`. Configure that integration in Codemagic using a dedicated App Store Connect API key with App Manager access. Store the Issuer ID, Key ID, and `.p8` file only in Codemagic.

Create an App Store Connect app record with bundle ID `com.smoothroute.rider` and an internal TestFlight group named `Internal Testers` before enabling automatic distribution.
