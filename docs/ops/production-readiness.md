# PlayMe Production Readiness

This checklist is the launch-practical operating baseline for the Firebase production backend.

## Monitoring

- Enable Crashlytics and Performance Monitoring for the iOS app before App Store release.
- Create Cloud Logging alert policies for:
  - Cloud Function error count above the normal baseline over 5 minutes.
  - Cloud Function p95 latency above the normal baseline over 10 minutes.
  - Spotify token/search failures, especially `429`, `500`, and `503`.
  - FCM send failures with invalid-token cleanup spikes.
- Review alerts weekly during beta and daily during launch week.

Suggested launch filters:

```text
jsonPayload.event="resolve_spotify_rate_limited"
jsonPayload.event="resolve_spotify_http_failed"
jsonPayload.event="resolve_spotify_token_mint_failed"
jsonPayload.event="push_send_failed"
jsonPayload.event="push_stale_token_cleanup_failed"
jsonPayload.event="rate_limit_failed_open"
jsonPayload.event="validate_invite_rate_limited"
jsonPayload.event="redeem_invite_failed"
```

Alert on any sustained non-zero rate during the first paid-acquisition week.
The filters intentionally rely on structured event names and avoid request
bodies, phone numbers, invite-code contents, or message text.

## App Check Rollout

The iOS app attaches `X-Firebase-AppCheck` to custom Cloud Function HTTP
requests. Functions default to monitor mode (`APP_CHECK_MODE` unset or
`monitor`): missing/invalid tokens are logged as `app_check_missing` or
`app_check_invalid` but not blocked.

After Firebase Console shows legitimate iOS traffic passing App Check, enforce
the sensitive HTTP endpoints:

```sh
# Set APP_CHECK_MODE=enforce in the Gen2 functions environment / deployment
# pipeline, then redeploy functions.
firebase deploy --only functions
```

Verify enforcement in staging before production. If legitimate clients are
blocked, return to monitor mode and inspect the App Check dashboard plus Cloud
Logging events.

## Public Phone Cleanup

New client writes store phone numbers only under
`users/{uid}/private/profile.phone`. Public profile rules no longer allow
client writes to `users/{uid}.phone`.

Before production rules deploy, run the cleanup in staging:

```sh
cd functions
GOOGLE_APPLICATION_CREDENTIALS=/path/to/staging-service-account.json \
FIREBASE_PROJECT_ID=riff-staging \
npm run cleanup:public-phone -- --dry-run
```

If the count looks right, rerun without `--dry-run`. Repeat once against
production during a quiet period, then deploy `firestore.rules`.

## Backups

- Enable Firestore Point-in-Time Recovery when budget allows.
- If PITR is not enabled, schedule Firestore exports to a locked Cloud Storage bucket.
- Run one restore drill into a non-production Firebase project before launch.
- Keep `firestore.rules` and `firestore.indexes.json` deployed from source control only.

## Staging Smoke Test

Use a separate Firebase project and service account. See
[`docs/ops/staging.md`](staging.md) for the minimal setup and manual smoke
checklist. Run:

```sh
cd functions
GOOGLE_APPLICATION_CREDENTIALS=/path/to/staging-service-account.json \
FIREBASE_PROJECT_ID=playme-staging \
node scripts/staging-load-test.js --users=20 --shares=50 --messages=50
```

Validate signup-like profile writes, friendship edges, song shares, message writes, and read queries. This is launch-traffic smoke coverage, not million-user load testing.

## Incident Runbooks

Use `docs/ops/runbooks.md` for rollback, secret rotation, FCM failures, Spotify/Odesli outages, and Firestore rules/index failures.
