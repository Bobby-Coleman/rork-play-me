# PlayMe Incident Runbooks

## Firebase Deploy Rollback

1. Identify the failed deploy in Firebase Console or Cloud Logging.
2. Re-deploy the last known-good `firestore.rules`, `firestore.indexes.json`, and `functions/index.js` from Git.
3. Validate signup, friend request, song send, listen receipt, and chat message flows in staging.
4. Deploy to production and watch function errors for 30 minutes.

## Spotify Secret Rotation

1. Create a new Spotify client secret in the Spotify developer dashboard.
2. Update the Firebase secret:

```sh
firebase functions:secrets:set SPOTIFY_CLIENT_SECRET
```

3. Deploy functions that use the secret.
4. Smoke test Spotify auth swap and refresh.
5. Revoke the old Spotify secret.

## FCM Notification Failure

1. Check Cloud Logging for `sendPush error` and stale-token cleanup entries.
2. Confirm APNs key/certificate status in Firebase Console.
3. Send a test notification to a known-good device token.
4. If invalid-token errors spike, verify clients are saving tokens under `users/{uid}/private/profile`.

## Spotify Or Odesli Outage

1. Confirm outage by checking function logs for Spotify `429`, `500`, or `503`.
2. Keep the app online using cached Spotify resolutions and Apple Music URLs.
3. Avoid clearing `spotifyResolutions`; it is the fallback cache.
4. Post-launch, consider temporary client messaging if the outage lasts longer than 30 minutes.

## Firestore Rules Or Index Failure

1. Stop production deploys.
2. Re-deploy the last known-good rules/indexes from Git.
3. For missing indexes, create the index from the Firestore error link, then backport to `firestore.indexes.json`.
4. Smoke test profile search, received/sent shares, chat inbox, and album/mixtape shares.
