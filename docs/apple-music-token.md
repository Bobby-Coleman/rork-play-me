# Apple Music developer token — provisioning

The iOS app talks to `api.music.apple.com` for catalog search, search
suggestions, and artist-details reads using a developer-only JWT signed
with Apple's MusicKit ES256 key. The JWT is minted server-side by the
`getMusicKitDeveloperToken` Cloud Function in `functions/index.js` so the
private `.p8` key never ships in the iOS binary.

This means **no user-facing MusicKit prompt is ever required for catalog
browsing** — search and artist pages work for every user (Spotify-flow
included) the moment they sign in. The MusicKit user prompt only fires
from `MusicServiceView` when the user explicitly picks Apple Music for
personalization.

## One-time setup (per Firebase environment)

You need three values from Apple's developer portal:

1. **Team ID** — 10-char string, shown at the top of
   <https://developer.apple.com/account>.
2. **MusicKit Key ID** — 10-char string for a key with MusicKit enabled.
3. **MusicKit `.p8` private key** — the file you download once when you
   create the key. Save it somewhere safe; you cannot redownload it.

### Creating the MusicKit key

1. <https://developer.apple.com/account/resources/authkeys/list> → "+".
2. Give it a name (e.g. `RIFF MusicKit`), tick **MusicKit**, click
   **Configure** and associate the key with your Music ID. Continue.
3. Register and **Download** the `AuthKey_<KEY_ID>.p8` file. Note the
   10-character Key ID shown next to it.

### Loading the secrets

Run from the repo root, replacing the bracketed placeholders. Each
command opens an editor or prompt where you paste the value.

```sh
firebase functions:secrets:set APPLE_MUSIC_TEAM_ID
# paste your 10-char Team ID, save, exit

firebase functions:secrets:set APPLE_MUSIC_KEY_ID
# paste the 10-char Key ID for the MusicKit .p8

firebase functions:secrets:set APPLE_MUSIC_PRIVATE_KEY
# paste the FULL contents of AuthKey_<KEY_ID>.p8, including the
# -----BEGIN PRIVATE KEY----- and -----END PRIVATE KEY----- lines.
```

### Deploying

```sh
firebase deploy --only functions:getMusicKitDeveloperToken
```

The first deploy after adding the secret will prompt you to confirm
binding the secret to the function. Accept it.

## Verifying

After deploy, hit the endpoint with a valid Firebase ID token:

```sh
TOKEN="<a-valid-firebase-id-token>"
curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  https://us-central1-<PROJECT_ID>.cloudfunctions.net/getMusicKitDeveloperToken
# expect: {"token":"eyJ...","expiresAt":1234567890}
```

You can sanity-check the JWT against Apple Music itself:

```sh
DEV_TOKEN="<value of token returned above>"
curl -sS \
  -H "Authorization: Bearer $DEV_TOKEN" \
  "https://api.music.apple.com/v1/catalog/us/search?term=olivia+rodrigo&types=songs&limit=1" \
  | head -c 200
# expect: a JSON body starting with {"results":{"songs":...
```

If you get a 401 from `api.music.apple.com`, double-check the Key ID and
Team ID match exactly and that the `.p8` you uploaded was the one bound
to the MusicKit identifier.

## Token lifecycle

- The Cloud Function signs JWTs with a 1-hour lifetime (`exp = iat +
  3600`). Apple permits up to 180 days; we keep it short so a leaked
  token is bounded.
- The iOS client (`AppleMusicTokenService`) caches the JWT in Keychain
  and refreshes silently on cache miss, near-expiry (within 5 min), or a
  401 from `api.music.apple.com`. The user never sees this.
- To rotate the `.p8`, just upload the new contents with
  `firebase functions:secrets:set APPLE_MUSIC_PRIVATE_KEY` and redeploy.
  Existing devices pick up new tokens on their next refresh; no app
  update is needed.

## Failure modes

- **Secrets not provisioned** → endpoint returns `503 unconfigured`. The
  iOS client surfaces "Search is temporarily unavailable" rather than
  silently empty results.
- **Bad `.p8`** → `jwt.sign` throws; endpoint returns `500 sign_failed`
  with the underlying error logged to Cloud Functions logs.
- **Wrong Team ID / Key ID** → `getMusicKitDeveloperToken` succeeds but
  `api.music.apple.com` returns 401. The client force-refreshes once
  (which produces the same bad JWT) and then surfaces the failure.
