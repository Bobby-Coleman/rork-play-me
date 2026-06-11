# Firebase Staging Setup

This is the smallest staging setup Riff needs before paid acquisition. It is a
practice field for Firestore rules, Cloud Functions, App Check, and smoke/load
scripts. Do not run load scripts against production.

## Create The Project

1. In Firebase Console, create a separate project, for example `riff-staging`.
2. Enable the same products used by production:
   - Authentication with Phone provider
   - Firestore
   - Cloud Functions
   - Cloud Storage
   - Cloud Messaging
   - App Check in monitor mode
3. Add an iOS app to the staging project and download its
   `GoogleService-Info.plist`.
4. Store the staging plist outside git, or keep it as a local-only file. Never
   replace the production plist in a committed change.

## Deploy To Staging

From the repo root:

```sh
firebase use --add
# Pick the staging project and give it alias "staging".

firebase use staging
firebase deploy --only firestore:rules,firestore:indexes,functions,storage
```

Before deploying production, switch back explicitly:

```sh
firebase use default
firebase deploy --only firestore:rules,firestore:indexes,functions,storage
```

## Run The Smoke Load Script

Use a staging service account only:

```sh
cd functions
GOOGLE_APPLICATION_CREDENTIALS=/path/to/staging-service-account.json \
FIREBASE_PROJECT_ID=riff-staging \
node scripts/staging-load-test.js --users=50 --shares=150 --messages=150 --invites=25
```

For launch rehearsal, increase volume gradually in staging:

```sh
GOOGLE_APPLICATION_CREDENTIALS=/path/to/staging-service-account.json \
FIREBASE_PROJECT_ID=riff-staging \
node scripts/staging-load-test.js --users=250 --shares=1000 --messages=1000 --invites=100
```

## Manual Smoke Checklist

Run these in staging after every rules/functions change:

- New user can validate an invite code and complete phone auth.
- New user can create profile and username.
- User can send a song to a friend.
- Recipient receives the share and the related DM.
- Friend request accept respects the 20-friend cap.
- Blocked user cannot write into the blocker's inbox.
- Account deletion removes private profile data and anonymizes history.
- `resolveSpotifyTrack` returns a result or a graceful no-match response.

## Keep It Simple

Staging does not need CI on day one. For the 5k-10k launch window, the goal is
only to avoid testing risky Firestore rules, App Check enforcement, Cloud
Functions, and destructive scripts directly against production.
