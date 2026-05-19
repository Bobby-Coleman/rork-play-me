# Riff Security Hardening — May 2026

This pass closed the highest-impact items from the OWASP Top 10 audit
and added two product-level safety features (per-user friend cap, OTP
resend throttle). What landed, what's deferred, and how to keep it
that way.

## Summary

| # | Area | Status | Notes |
|---|------|--------|-------|
| 1 | Lock unauth Cloud Functions | ✅ Landed | Deprecated `swap`/`refresh`/`getTokens`/`auth` return 410. `validateInviteCode` now has per-IP token bucket (20/10min). `resolveSpotifyTrack` + `redeemInviteCode` already required Bearer ID token. |
| 2 | Firestore rules hardening | ✅ Landed | Field allowlists on `users/{uid}` writes; conversation update key gate; message length cap (2000); reaction emoji allowlist; `spotifyResolutions` writes now admin-only; friend-cap gate on friend doc create. |
| 3 | Friend-gate DMs + per-UID throttles | ⏳ Deferred | The current participant-gate is already strong: a conversation must exist before either side can send, and conversation creation requires participant === auth.uid. Pushing further to "must be friends" would break the Discovery reply flow. Per-UID throttles need a Cloud Function trigger refactor; see "Follow-ups". |
| 4 | App Check | ⏳ Deferred | Requires Firebase Console + `FirebaseAppCheck` SDK addition. See "Follow-ups". |
| 5a | PII print gating | ✅ Landed | Phone numbers, message text, contact full names wrapped in `#if DEBUG`. ShazamKit prints already gated. |
| 5b | ChottuLink API key rotation path | ✅ Landed | Key moved out of `PlayMeApp.swift` into `Config.plist` (gitignored). `Config.plist.template` documents the values. **You must rotate the key — the previous value is in the git history.** See "Required follow-up actions". |
| 6 | Cost hygiene | ✅ Landed | Daily scheduled `cleanupPushDedupe` sweeper; `requestPendingSharesClaim` no-ops within a session; `loadBlockedUsers` switched from N+1 to bounded-concurrency fan-out. |
| 7 | Privacy compliance | ✅ Landed | `PrivacyInfo.xcprivacy` added; `NSPrivacyPolicyURL` + `NSTermsOfServiceURL` set in Info.plist. **You must publish the policy at `https://playme.app/privacy` before App Store submission.** |
| 8 | Crashlytics / structured logging | ⏳ Deferred | Requires Firebase Console enable. See "Follow-ups". |
| – | Friend cap (8 per user, configurable) | ✅ Landed | Default 8 in `Config.DEFAULT_FRIEND_LIMIT`, `firestore.rules`, and `functions/index.js`. Per-account override via `users/{uid}.friendLimit`. Enforced at rules level (soft) + Cloud Function trigger (hard). UI surfaces "{n} of {limit} friends" + disables Accept button at cap. |
| – | OTP resend cooldown + countdown | ✅ Landed | Both OTP entry views (`OTPVerifyView` and `OTPVerificationView`) show "Resend code in m:ss" with a `monospacedDigit` countdown. Cooldown escalates per session (30s → 60s → 120s, capped); session resend cap = 5 (`Config.OTP_RESEND_SESSION_MAX`). |

## What changed, in code

### Firestore rules (`firestore.rules`)

- **Users field allowlist.** `users/{uid}` create/update now reject any
  field not in `userDocClientWriteableFields()`. This kills the entire
  category of "client tampers with their own `friendCount`, faking
  premium subscription state, or moving `fcmToken` from the private
  doc to the world-readable public doc" attacks.
- **Friends gate.** `friends/{friendId}` create now requires:
  1. Either an outstanding `friendRequests/{friendId}` on the owner's
     side (path A — owner accepting), OR an outstanding
     `outgoingFriendRequests/{auth.uid}` on the owner's side (path B
     — peer creating the mirror row);
  2. The owner is under their per-user friend cap
     (`friendCount < friendLimit`).
- **Conversation field allowlist.** Updates restricted to a
  per-participant key set. Specifically, `lastReadAt_<uid>` may only
  be written by `<uid>` themselves — this closes the "sender forges a
  read receipt by writing the other participant's lastReadAt" vector.
- **Message body cap.** Messages with `text.size() > 2000` are
  rejected by rules.
- **Reaction emoji allowlist.** Reactions are constrained to the six
  iMessage-style tapback options (`❤️ 👍 👎 😂 ‼️ ❓`). Prevents
  reaction-based content abuse (e.g. someone reacting with a slur).
- **`spotifyResolutions` writes locked.** Was open to any signed-in
  user; one user could redirect every other user's "Open in Spotify"
  click to a spam URL. Now admin-only — the `resolveSpotifyTrack`
  Cloud Function is the canonical writer.

### Cloud Functions (`functions/index.js`)

- **Deprecated Spotify OAuth endpoints disabled.** `swap`, `refresh`,
  `getTokens`, `auth` all return 410 with a clear message. They were
  unauthenticated and exposed our `SPOTIFY_CLIENT_SECRET`-backed
  token swap to any caller on the internet.
- **`validateInviteCode` rate-limited.** 20 checks per IP per 10
  minutes. The endpoint can't strictly require a Bearer token (the
  user hasn't signed in yet) but per-IP throttling makes brute force
  uneconomic. Fails open on Firestore errors — onboarding doesn't
  get bricked if rate-limit reads fail.
- **`onFriendCreated` / `onFriendDeleted` triggers.** Maintain
  `friendCount` on the user doc. `onFriendCreated` also enforces a
  hard cap by removing the most-recently-added friend if the count
  exceeded the limit (rare race-loser case; soft cap in rules catches
  the common path).
- **`resolveSpotifyTrack` now writes the cache.** Server-side write
  to `spotifyResolutions` replaces the (now disallowed) client write.
- **`cleanupPushDedupe` scheduled job.** Runs daily, deletes
  expired `pushDedupe` entries in 500-doc batches.
- **`consumeRateLimitToken` helper + `rateLimits` collection.**
  Lightweight Firestore token bucket. Currently used by
  `validateInviteCode`; can be reused for any future per-IP/UID gate.

### iOS

- **`Config.swift` + `Config.plist` (gitignored).** ChottuLink API key
  is now read at runtime from `Config.plist` or the environment.
  `Config.plist.template` documents the keys for new devs.
- **`Config.DEFAULT_FRIEND_LIMIT = 8`** is the canonical client-side
  value. Mirror of the rules and Cloud Function defaults.
- **`Config.otpResendCooldown(forAttempt:)`** computes the OTP resend
  cooldown. Escalates 30s → 60s → 120s (capped).
- **PII print statements wrapped in `#if DEBUG`.** Phone numbers,
  contact full names, message text snippets, Shazam matches.
  Production logs no longer leak PII.
- **`loadBlockedUsers` fan-out.** Replaces N+1 profile fetches with a
  `withTaskGroup`-based concurrent fetch, capped at 25 parallel
  reads.
- **`requestPendingSharesClaim(force:)`** no-ops after the first
  successful claim per session unless `force: true` is passed
  (currently only the post-registration handoff forces).
- **`acceptFriendRequestChecked`** returns a typed result
  (`.success` / `.atCap(limit:)` / `.failed`). The Add Friends view
  reads `appState.friendCap` to disable the Accept button and show
  "{n} of {limit} friends" in the header.
- **OTP countdown.** `formattedCountdown(_:)` renders `m:ss` with
  `monospacedDigit()` so the resend label doesn't jitter as the
  timer ticks down.
- **`PrivacyInfo.xcprivacy`** declares phone, name, user ID,
  contacts, message content, audio, and device token under the
  Required Reasons API + collected data types.

## Required follow-up actions (you, not the agent)

1. **Rotate the ChottuLink API key.** The previous value
   (`c_app_3GyFRIbGUgB7iWYwMPEOM2Q7ogTMxPSf`) is in the git history
   under `ios/PlayMe/PlayMeApp.swift`. Generate a new key in the
   ChottuLink dashboard, drop it into `ios/PlayMe/Config.plist`
   locally, and configure your CI to inject it into the production
   build. The previous key should be revoked.
2. **Publish the privacy policy + terms of service** at
   `https://playme.app/privacy` and `/terms` before App Store
   submission. Update the URLs in `ios/PlayMe/Info.plist` if you
   host elsewhere.
3. **Deploy the new Firestore rules + Cloud Functions.** Run
   `firebase deploy --only firestore:rules,functions` to ship the
   server-side changes. Rules deploy is essentially instant; the new
   `onFriendCreated`/`onFriendDeleted`/`cleanupPushDedupe` functions
   need a deploy + the `cleanupPushDedupe` scheduler needs Cloud
   Scheduler enabled in the project (free tier handles this).
4. **Backfill `friendCount` for existing users.** New triggers only
   fire on new friend writes. To seed the count for existing users,
   run a one-shot script that iterates `users/*` and sets
   `friendCount = countOf(users/{uid}/friends/*)`. (Or accept that
   existing users will accrue accurate counts as their next friend
   add/remove fires the trigger — the soft cap is wrong by at most
   the current count value, which is bounded by the cap anyway.)

## Follow-ups (deferred — listed in order of recommended priority)

### Tier 4: Firebase App Check

Adds device attestation (App Attest on iOS) so requests to Cloud
Functions can verify they originate from a legitimate app install
rather than a script with a stolen Bearer token. To enable:

1. In Firebase Console → App Check, register the iOS app with App
   Attest as the provider.
2. Add `FirebaseAppCheck` to the Xcode project's Swift package
   manifest.
3. In `PlayMeApp.swift` `init` (BEFORE `FirebaseApp.configure()`),
   set the provider:
   ```swift
   let providerFactory = AppCheckDebugProviderFactory()  // for DEBUG
   // or AppAttestProviderFactory() in release
   AppCheck.setAppCheckProviderFactory(providerFactory)
   ```
4. In Cloud Functions, set `enforceAppCheck: true` on the `onRequest`
   options for each callable that should require it (start with
   `resolveSpotifyTrack`, `redeemInviteCode`, `validateInviteCode`).
5. Roll out gradually — start in "monitor" mode in Firebase Console
   to see the rejection rate before flipping to "enforce".

### Per-UID rate limiting on message send + friend requests

`consumeRateLimitToken` is already in `functions/index.js`. To wire
it into the message send path without a breaking rule change, add a
`onNewMessage` enforcement step that records writes per UID and, if
a threshold (say 30 messages per minute) is exceeded, sets a
`users/{uid}.suspendedAt` flag. The DM rule then reads
`!users/{uid}.suspendedAt` (or a derived `isActive` field that
expires automatically). This keeps the rule's `get()` budget small
(one per write) and gives forensics a clear suspend log.

### Tier 8: Crashlytics + structured logging

1. In Firebase Console → Crashlytics, enable for the iOS app.
2. Add `FirebaseCrashlytics` to the Swift package manifest.
3. The first session after deploy automatically uploads the dSYM and
   starts collecting crashes.
4. For structured server logs, wrap the existing `console.log` calls
   in functions with a small helper that emits JSON so Cloud Logging
   can index by field. See `JSON.stringify({ event: "...", ... })`
   examples already used in `cascadeDeleteUser` and
   `onFriendCreated`.

### Keychain migration for phone / profile cache

The phone number and a small profile cache currently live in
`UserDefaults`. Migrating to Keychain is straightforward (replace the
`UserDefaults.standard.set(...) / .string(forKey:)` calls with a
Keychain helper) but the migration must be one-shot-resilient
(detect old UserDefaults values, copy to Keychain, delete from
UserDefaults). Worth doing, low urgency — UserDefaults is per-app
and not exfiltratable without device compromise on iOS.

## Scale & cost notes

- **Firestore reads per friend add.** Rule `get()` of the user doc
  (1 read) + existing `exists()` checks for friend request docs
  (2 reads). Well under the 10/eval budget.
- **`cleanupPushDedupe`** Free tier handles this. 500-doc batches at
  most 20 iterations = max 10K deletes/day per run. Realistic load
  even at 100K MAU is well below that.
- **Per-IP throttle on `validateInviteCode`** Each invite check is
  now 1 read + 1 write (the rate-limit doc) + 1 read (the invite
  code itself). At 100 invite checks per second across the app
  that's well within free tier limits.

## Verifying

```bash
# Lint Cloud Functions
cd functions && npm run check

# Deploy
firebase deploy --only firestore:rules,functions

# Build the iOS app
# (uses XcodeBuildMCP `build_sim` in this agent setup)
```
