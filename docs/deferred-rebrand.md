# Deferred RIFF rebrand pass

The user-facing onboarding rebuild rebranded every visible "Play Me" /
"PlayMe" string to "RIFF". The items below were intentionally **not**
migrated in that pass because they touch backend identifiers, signing,
or release-channel config and need to be migrated as a coordinated
mechanical change with infra updates (Firebase project rename, APNs
entitlements, Cloud Function renames, Universal Link domain rotation,
etc.).

When you're ready to do the second pass, here's everything that's still
saying PlayMe:

## Bundles + project metadata

- `ios/PlayMe.xcodeproj/` — project name + target name
- `ios/PlayMe/PlayMeApp.swift` — `struct PlayMeApp: App {}`
- `ios/PlayMeWidget/` — widget extension target name + `PlayMeWidget`
  type names
- `ios/PlayMeNotificationService/` — notification service extension
  target name
- Bundle identifiers (`app.rork.playme.*`) — Apple developer console +
  Xcode targets
- Widget product display name "PlayMe widget"
- App Group identifier `group.app.rork.playme.shared`
  (`ios/PlayMe/Shared/WidgetSharedConstants.swift`,
  `ios/PlayMe/PlayMe.entitlements`)

## Info.plist usage descriptions

These are user-facing (iOS prompts) but tied to the bundle ID so they
ride along with the bundle rename:

- `NSAppleMusicUsageDescription`
- `NSContactsUsageDescription`
- `NSPhotoLibraryUsageDescription`

## URL scheme

- Custom URL scheme `playme://` in `ios/PlayMe/Info.plist`
  (`CFBundleURLSchemes`) and `Spotify`'s callback `playme://spotify-callback`
  in `functions/index.js`
- `ContentView.handleIncomingURL` matches `url.scheme == "playme"`

## Universal Links

- Domain `playme.chottu.link` in `ios/PlayMe/PlayMe.entitlements`
  (`com.apple.developer.associated-domains`) and
  `ios/PlayMe/Services/DeepLinkService.swift` (`createInviteLink`).

## Firestore + Cloud Functions

- Firestore collection names (`shares`, `mixtapeShares`, `albumShares`,
  `pendingShares`, `claimRequests`, etc.) — the scheme itself is fine,
  no rename needed.
- Cloud Function names (`onNewShare`, `onNewMessage`, `swap`,
  `resolveSpotifyTrack`, `validateInviteCode`, `redeemInviteCode`, …)
  — these are PUBLIC URLs; renaming them needs an old-version
  deprecation step.
- Firebase project ID itself (`rork-play-me`) — biggest blast radius;
  effectively requires a brand-new Firebase project.

## Spotify + APNs config

- Spotify token-swap redirect URI `playme://spotify-callback`
- APNs topic + push entitlements
- `support@rork.app?subject=PlayMe%20Support` mailto subject (only a
  hint, not infra; safe to flip whenever).

## Remaining code references (cosmetic / comments)

- Source-code comments and log strings that mention PlayMe/Play Me —
  cleanup is mechanical but cosmetic only.

## Suggested sequence

1. Rename the Xcode targets + bundle IDs (one PR, no functional change).
2. Migrate Universal Links + URL scheme + entitlements.
3. Stand up a new Firebase project under the new name; mirror data;
   flip the iOS bundle's `GoogleService-Info.plist`.
4. Rename Cloud Functions in two phases: deploy under new names while
   keeping old names live, switch the iOS callers, delete the old
   names after a few releases.
