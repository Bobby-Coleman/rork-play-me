# Curated grid uploader

Tools for rotating the album-art grid that PlayMe shows on the
Discovery hero (`ios/PlayMe/Views/Discovery/DiscoveryView.swift`) and
the onboarding "Send your first song" screen
(`ios/PlayMe/Views/Onboarding/SendFirstSongView.swift`). Both surfaces
read the same Firestore document on cold launch, so a single upload
rotates both grids.

```
authoring   curated-grid.json   (this folder, checked into git)
upload      node scripts/uploadCuratedGrid.js
lookup      node scripts/lookupArtwork.js "Drake One Dance"
target      Firestore: curatedGrids/current
ios entry   ios/PlayMe/Services/CuratedSongGridProvider.swift
```

## One-time setup

1. **Generate a service account key** in the Firebase Console:
   *Project Settings → Service Accounts → Generate new private key*.
   Save the downloaded JSON as `functions/scripts/service-account.json`.
   The repo's `.gitignore` already blocks this filename — never commit it.

2. **Point Application Default Credentials at it.** From the repo
   root:

   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/functions/scripts/service-account.json"
   ```

   Stick that line in your `~/.zshrc` (or equivalent) if you want it
   set every shell.

3. **Confirm `firebase-admin` is installed.** It already is via
   `functions/package.json`, so this should be a no-op:

   ```bash
   cd functions && npm install
   ```

## Authoring the list

Edit `curated-grid.json`. Each entry follows the `GridSong` shape used
by the iOS side (`ios/PlayMe/Models/GridSong.swift`):

```json
[
  {
    "id": "drake-one-dance",
    "albumArtURL": "https://is1-ssl.mzstatic.com/.../600x600bb.jpg",
    "title": "One Dance",
    "artist": "Drake"
  },
  {
    "id": "billie-wildflower",
    "albumArtURL": "https://is1-ssl.mzstatic.com/.../600x600bb.jpg",
    "title": "WILDFLOWER",
    "artist": "Billie Eilish"
  }
]
```

Field rules:

| Field | Required | Rendered? | Notes |
|---|---|---|---|
| `id` | yes | no | Any unique stable string. `kebab-case-artist-title` is the convention. |
| `albumArtURL` | yes | yes (only field that's rendered) | Public, no-auth, ~600x600 square JPG/PNG. |
| `title` | no | no | Bookkeeping only; never displayed. |
| `artist` | no | no | Bookkeeping only; never displayed. |

The grid renders only the cover image — singles, albums, EPs,
compilations, custom artwork all work identically. Mix freely. Dedup
is enforced client-side on `albumArtURL`.

### Resolving artwork URLs quickly

The iTunes Search API returns stable, no-auth Apple CDN URLs. The
`lookupArtwork.js` helper wraps it and upgrades the result to 600x600:

```bash
node scripts/lookupArtwork.js "Drake One Dance"
# → { "id": "drake-one-dance", "albumArtURL": "...600x600bb.jpg", "title": "One Dance", "artist": "Drake" }

node scripts/lookupArtwork.js --entity album "Frank Ocean Blonde"
# → uses the album cover instead of any individual single

node scripts/lookupArtwork.js --id custom-slug "Sufjan Stevens The Predatory Wasp"
```

You can also paste any other public square image URL (Spotify CDN,
custom S3, etc.) — the source doesn't matter as long as it's
fetchable.

## Uploading

```bash
cd functions
node scripts/uploadCuratedGrid.js
```

The script:

1. Parses `curated-grid.json`.
2. Validates that every entry has an `id` and an http(s) `albumArtURL`,
   that `id`s are unique, and that the list is non-empty (refuses to
   upload an empty array — that would clobber the live grid).
3. HEAD-checks every URL with up to 8 in flight; aborts before
   writing if any returns non-2xx.
4. Writes `{ items, updatedAt: <serverTimestamp> }` to
   `curatedGrids/current` in Firestore.

iOS clients pick up the change on their **next cold launch**. The
list is cached in `UserDefaults` (key `GridSong.CuratedCache.v1`) so
repeat launches paint instantly without a network round-trip.

## How long until users see it

| Surface | Latency |
|---|---|
| Cold launch on a fresh install | ~150–300 ms after launch (one Firestore read; bundled seed paints first) |
| Cold launch with prior cache | Cached list paints instantly; new list takes effect on the cold launch *after* this one |
| Hot launch (app already in memory) | Not refreshed; takes effect on the next cold launch |

If you ever need same-session refresh, the comment at the top of
`ios/PlayMe/Services/CuratedSongGridProvider.swift` outlines the
snapshot-listener path. Not wired today.

## Sizing guidance

- Sweet spot: 30–80 items.
- Hard ceiling: ~150 items before bitmap memory becomes a concern on
  older devices. The grid prefetches every URL into memory cache on
  appear.
- Each entry is ~100 bytes. 100 items ≈ 10 KB Firestore document.
  Doc size cap is 1 MB so you won't hit it.

## Troubleshooting

- `Error: Could not load the default credentials` → `GOOGLE_APPLICATION_CREDENTIALS` not set or pointing at a missing file. Re-run the `export` line above from the repo root.
- `the following URLs failed HEAD/GET` → fix or remove the listed entries before re-running. iTunes `mzstatic` URLs occasionally return 403 to HEAD; the script falls back to GET automatically, so a real 404 here means the artwork has actually moved.
- `curated-grid.json is empty; nothing to upload` → populate the file first; the script intentionally refuses to upload an empty list.
- Upload succeeded but the iOS app still shows the old list → it's cached. Force-quit the app and relaunch.
