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

## Backups

- Enable Firestore Point-in-Time Recovery when budget allows.
- If PITR is not enabled, schedule Firestore exports to a locked Cloud Storage bucket.
- Run one restore drill into a non-production Firebase project before launch.
- Keep `firestore.rules` and `firestore.indexes.json` deployed from source control only.

## Staging Smoke Test

Use a separate Firebase project and service account. Run:

```sh
cd functions
GOOGLE_APPLICATION_CREDENTIALS=/path/to/staging-service-account.json \
FIREBASE_PROJECT_ID=playme-staging \
node scripts/staging-load-test.js --users=20 --shares=50 --messages=50
```

Validate signup-like profile writes, friendship edges, song shares, message writes, and read queries. This is launch-traffic smoke coverage, not million-user load testing.

## Incident Runbooks

Use `docs/ops/runbooks.md` for rollback, secret rotation, FCM failures, Spotify/Odesli outages, and Firestore rules/index failures.
