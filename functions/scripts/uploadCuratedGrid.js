// Uploads functions/scripts/curated-grid.json to the Firestore document
// curatedGrids/current, which the iOS app reads via
// CuratedSongGridProvider on cold launch (see
// ios/PlayMe/Services/CuratedSongGridProvider.swift). The full reading
// pipeline is documented at ios/PlayMe/ViewModels/SongGridViewModel.swift.
//
// Usage (from the repo root):
//   export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/functions/scripts/service-account.json"
//   cd functions && node scripts/uploadCuratedGrid.js
//
// The script validates each entry, refuses to upload an empty or
// invalid list (so a misconfiguration can never wipe the live grid),
// HEAD-checks every albumArtURL to surface dead CDN links before
// writing, then performs a single Firestore write.

const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

const SOURCE_FILE = path.join(__dirname, "curated-grid.json");
const COLLECTION = "curatedGrids";
const DOCUMENT = "current";
const HEAD_CHECK_TIMEOUT_MS = 8000;
const HEAD_CHECK_CONCURRENCY = 8;

function fail(msg) {
  console.error(`uploadCuratedGrid: ${msg}`);
  process.exit(1);
}

function loadAndValidate() {
  if (!fs.existsSync(SOURCE_FILE)) {
    fail(`source file not found: ${SOURCE_FILE}`);
  }

  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(SOURCE_FILE, "utf8"));
  } catch (err) {
    fail(`invalid JSON in ${SOURCE_FILE}: ${err.message}`);
  }

  if (!Array.isArray(parsed)) {
    fail("expected the JSON root to be an array of GridSong objects");
  }

  // An empty list would clobber the live grid with nothing — almost
  // always a misconfiguration (forgot to populate the file). The iOS
  // side ignores empty Firestore returns and falls back to the
  // bundled seed, but uploading an empty array still costs a write
  // and leaves a misleading audit trail. Refuse loudly instead.
  if (parsed.length === 0) {
    fail("curated-grid.json is empty; nothing to upload");
  }

  const seenIds = new Set();
  const seenArt = new Set();
  const items = parsed.map((raw, i) => {
    if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
      fail(`entry [${i}] is not an object`);
    }
    const id = raw.id;
    const albumArtURL = raw.albumArtURL;

    if (typeof id !== "string" || id.trim() === "") {
      fail(`entry [${i}] missing required string field 'id'`);
    }
    if (typeof albumArtURL !== "string" || albumArtURL.trim() === "") {
      fail(`entry [${i}] missing required string field 'albumArtURL'`);
    }
    if (!/^https?:\/\//i.test(albumArtURL)) {
      fail(`entry [${i}] albumArtURL must be an http(s) URL: ${albumArtURL}`);
    }

    if (seenIds.has(id)) {
      fail(`entry [${i}] duplicate id '${id}'`);
    }
    seenIds.add(id);

    // Soft warning only — the iOS side dedupes by albumArtURL so this
    // isn't fatal, but it's almost always unintentional.
    if (seenArt.has(albumArtURL)) {
      console.warn(`uploadCuratedGrid: warning — duplicate albumArtURL at entry [${i}] (will be deduped client-side)`);
    }
    seenArt.add(albumArtURL);

    const item = { id: id.trim(), albumArtURL: albumArtURL.trim() };
    if (typeof raw.title === "string" && raw.title.trim() !== "") {
      item.title = raw.title.trim();
    }
    if (typeof raw.artist === "string" && raw.artist.trim() !== "") {
      item.artist = raw.artist.trim();
    }
    return item;
  });

  return items;
}

async function headCheck(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), HEAD_CHECK_TIMEOUT_MS);
  try {
    // Some CDNs (including mzstatic on certain edges) return 405 for
    // HEAD but 200 for GET. Fall back to GET-with-no-body if HEAD is
    // refused.
    let res = await fetch(url, { method: "HEAD", signal: controller.signal });
    if (res.status === 405 || res.status === 403) {
      res = await fetch(url, { method: "GET", signal: controller.signal });
    }
    return { ok: res.ok, status: res.status };
  } catch (err) {
    return { ok: false, status: 0, error: err.message };
  } finally {
    clearTimeout(timer);
  }
}

async function headCheckAll(items) {
  const failures = [];
  let nextIdx = 0;

  async function worker() {
    while (true) {
      const idx = nextIdx++;
      if (idx >= items.length) return;
      const item = items[idx];
      const { ok, status, error } = await headCheck(item.albumArtURL);
      if (!ok) {
        failures.push({
          idx,
          id: item.id,
          url: item.albumArtURL,
          status,
          error,
        });
      }
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(HEAD_CHECK_CONCURRENCY, items.length) }, worker)
  );
  return failures;
}

async function main() {
  const items = loadAndValidate();
  console.log(`uploadCuratedGrid: validated ${items.length} entries; HEAD-checking URLs...`);

  const failures = await headCheckAll(items);
  if (failures.length > 0) {
    console.error("uploadCuratedGrid: the following URLs failed HEAD/GET — fix or remove them before uploading:");
    for (const f of failures) {
      const reason = f.error ? f.error : `HTTP ${f.status}`;
      console.error(`  [${f.idx}] ${f.id}  ${f.url}  (${reason})`);
    }
    process.exit(1);
  }
  console.log("uploadCuratedGrid: all URLs returned 2xx; writing to Firestore...");

  // Application Default Credentials. Set via:
  //   export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/functions/scripts/service-account.json"
  // The service-account.json is generated from
  //   Firebase Console -> Project Settings -> Service Accounts -> Generate new private key
  // and is gitignored.
  if (!admin.apps.length) {
    admin.initializeApp();
  }

  const ref = admin.firestore().collection(COLLECTION).doc(DOCUMENT);
  await ref.set({
    items,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`uploadCuratedGrid: wrote ${items.length} items to ${COLLECTION}/${DOCUMENT}.`);
  console.log("uploadCuratedGrid: iOS clients will pick up the change on their next cold launch.");
}

main().catch((err) => {
  console.error(`uploadCuratedGrid: unexpected error: ${err && err.stack ? err.stack : err}`);
  process.exit(1);
});
