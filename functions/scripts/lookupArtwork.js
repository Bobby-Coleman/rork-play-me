// CLI helper that turns a free-form "artist - title" query into a
// GridSong JSON object suitable for pasting into curated-grid.json.
//
// Hits the public iTunes Search API (no key, no auth, stable schema)
// and upgrades artworkUrl100 from 100x100bb to 600x600bb to match the
// resolution the iOS grid expects. Same upgrade rule used in
// ios/PlayMe/Services/ChartSongGridProvider.swift.
//
// Usage examples:
//   node scripts/lookupArtwork.js "Drake One Dance"
//   node scripts/lookupArtwork.js "Bad Bunny - Ojitos Lindos"
//   node scripts/lookupArtwork.js --entity album "Frank Ocean Blonde"
//
// Flags:
//   --entity song|album   pick which iTunes entity to search (default: song)
//   --country US|GB|...   storefront ISO code (default: US)
//   --id <slug>           override the generated id; otherwise derived
//                         as "<artist>-<title>" lowercased + dashed.
//
// Prints a single JSON object to stdout on success; exits non-zero on
// no match. Pipe / append to your authoring file as needed.

const ENDPOINT = "https://itunes.apple.com/search";

function parseArgs(argv) {
  const args = { entity: "song", country: "US", id: null, query: [] };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--entity") {
      args.entity = argv[++i];
    } else if (a === "--country") {
      args.country = argv[++i];
    } else if (a === "--id") {
      args.id = argv[++i];
    } else if (a === "--help" || a === "-h") {
      printUsage();
      process.exit(0);
    } else {
      args.query.push(a);
    }
  }
  return args;
}

function printUsage() {
  console.error(
    [
      "Usage: node scripts/lookupArtwork.js [--entity song|album] [--country US] [--id slug] <query...>",
      "Example: node scripts/lookupArtwork.js \"Drake One Dance\"",
    ].join("\n")
  );
}

function slugify(s) {
  return s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function upgradeArtwork(url) {
  if (typeof url !== "string") return null;
  return url.replace("100x100bb", "600x600bb");
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.query.length === 0) {
    printUsage();
    process.exit(2);
  }
  // Strip a leading dash separator if the user wrote "Artist - Title"
  // so the search term reads as "Artist Title" — iTunes ranks bare
  // term concatenations more reliably than dash-separated ones.
  const term = args.query.join(" ").replace(/\s+-\s+/g, " ").trim();

  const url = new URL(ENDPOINT);
  url.searchParams.set("term", term);
  url.searchParams.set("entity", args.entity);
  url.searchParams.set("country", args.country);
  url.searchParams.set("limit", "1");

  let res;
  try {
    res = await fetch(url.toString());
  } catch (err) {
    console.error(`lookupArtwork: network error: ${err.message}`);
    process.exit(1);
  }
  if (!res.ok) {
    console.error(`lookupArtwork: iTunes Search returned HTTP ${res.status}`);
    process.exit(1);
  }

  const data = await res.json();
  const hit = (data && Array.isArray(data.results) && data.results[0]) || null;
  if (!hit) {
    console.error(`lookupArtwork: no match for "${term}" (entity=${args.entity})`);
    process.exit(3);
  }

  const upgraded = upgradeArtwork(hit.artworkUrl100);
  if (!upgraded) {
    console.error(`lookupArtwork: match returned no artworkUrl100 (raw response: ${JSON.stringify(hit)})`);
    process.exit(4);
  }

  const title =
    args.entity === "album"
      ? hit.collectionName
      : hit.trackName || hit.collectionName;
  const artist = hit.artistName || "";

  const id =
    args.id && args.id.trim() !== ""
      ? args.id.trim()
      : slugify(`${artist} ${title}`);

  const out = {
    id,
    albumArtURL: upgraded,
    title: title || undefined,
    artist: artist || undefined,
  };
  // Strip undefined keys so the printed object stays minimal.
  for (const k of Object.keys(out)) if (out[k] === undefined) delete out[k];

  process.stdout.write(JSON.stringify(out, null, 2) + "\n");
}

main();
