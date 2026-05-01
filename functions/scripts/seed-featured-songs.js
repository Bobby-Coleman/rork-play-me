#!/usr/bin/env node

const admin = require("firebase-admin");

const projectId =
  process.env.FIREBASE_PROJECT_ID ||
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "rork-play-me";

const shouldWrite = process.argv.includes("--write");
const limitArg = process.argv.find((arg) => arg.startsWith("--limit="));
const limit = limitArg ? Number(limitArg.slice("--limit=".length)) : Infinity;
const minimumWriteCountArg = process.argv.find((arg) => arg.startsWith("--minimum-write-count="));
const minimumWriteCount = minimumWriteCountArg ? Number(minimumWriteCountArg.slice("--minimum-write-count=".length)) : 100;
const requestDelayMs = 350;

const requestedSongs = [
  { title: "The OOZ", artist: "King Krule" },
  { title: "Jour 1596", artist: "Hildegard, Helena Deland, Ouri" },
  { title: "It's You", artist: "Cruza" },
  { title: "Belly of the Whale", artist: "Searows" },
  { title: "How Much Is Weed?", artist: "Dominic Fike" },
  { title: "God Is a Circle", artist: "Yves Tumor" },
  { title: "Janie", artist: "Ethel Cain" },
  { title: "CY", artist: "Mother Soki" },
  { title: "Coasting", artist: "Fine" },
  { title: "HARDLY EVER SMILE (without you)", artist: "POiSON GiRL FRiEND" },
  { title: "Welcome To My Island", artist: "Caroline Polachek" },
  { title: "Chosen", artist: "Blood Orange, Caroline Polachek" },
  { title: "Dogfish", artist: "Oxis" },
  { title: "スカイレストラン", artist: "Hi-Fi Set" },
  { title: "Camino Del Sol", artist: "Antena" },
  { title: "All Things Heavy", artist: "Mynolia" },
  { title: "Handle", artist: "Officer John" },
  { title: "Searching", artist: "Ronald Langestraat" },
  { title: "Roll Like A Dummy", artist: "Late Verlane" },
  { title: "talk with your Teeth", artist: "Helen Sun" },
  { title: "Let It Die", artist: "Feist" },
  { title: "Taking What's Not Yours", artist: "TV Girl" },
  { title: "A Different Arrangement", artist: "Black Marble" },
  { title: "It's Glass", artist: "Dutch Interior" },
  { title: "If You Only Knew", artist: "Acetone" },
  { title: "de moi à moi je crois que j'explose", artist: "Céline Dessberg" },
  { title: "Object 9", artist: "Samba Jean-Baptiste" },
  { title: "Sky Record", artist: "Dan English" },
  { title: "nada", artist: "boylife, Porches" },
  { title: "Coyote", artist: "Emile Mosseri" },
  { title: "Help", artist: "Duval Timothy" },
  { title: "Os Mutantes", artist: "Os Mutantes" },
  { title: "Fleetwood Mac", artist: "Fleetwood Mac" },
  { title: "Mama's Gun", artist: "Erykah Badu" },
  { title: "The Academy", artist: "Lutalo" },
  { title: "Pirouette", artist: "Ain't" },
  { title: "Stratosphere", artist: "Duster" },
  { title: "Tidal", artist: "Fiona Apple" },
  { title: "Apollo XXI", artist: "Steve Lacy" },
  { title: "Waking Up", artist: "EXUM, Maxi" },
  { title: "Ö", artist: "Fcukers" },
  { title: "Equus Caballus", artist: "Men I Trust" },
  { title: "Midnight Request Line", artist: "Qendresa" },
  { title: "It's a Pleasure", artist: "Baxter Dury" },
  { title: "Mind Palace Music", artist: "@" },
  { title: "The New Abnormal", artist: "The Strokes" },
  { title: "Melt", artist: "Not for Radio" },
  { title: "Great Big Wild Oak", artist: "skirts" },
  { title: "From The Sun", artist: "Unknown Mortal Orchestra" },
  { title: "Your Day Will Come", artist: "Chanel Beads" },
  { title: "Crickets", artist: "Hollis Howard" },
  { title: "Slugger", artist: "DERBY" },
  { title: "Emo Regulation", artist: "RIP Swirl, Ydegirl" },
  { title: "Letter Blue", artist: "Wet" },
  { title: "Speaking in Tongues", artist: "Talking Heads" },
  { title: "Fresh Air", artist: "HOMESHAKE" },
  { title: "Heliophilia", artist: "24thankyou" },
  { title: "Around the Fur", artist: "Deftones" },
  { title: "Private Life", artist: "Tempers" },
  { title: "DHL", artist: "Frank Ocean" },
  { title: "Doris", artist: "Earl Sweatshirt" },
  { title: "Stars Above", artist: "sweet93" },
  { title: "Issy", artist: "Zack Villere, Mulherin, Phoenix James" },
  { title: "Big Fish Theory", artist: "Vince Staples" },
  { title: "My Way", artist: "ProdWithFlavor" },
  { title: "I quit", artist: "HAIM" },
  { title: "No One Noticed", artist: "The Marías" },
  { title: "Two Star & The Dream Police", artist: "Mk.gee" },
  { title: "Som time", artist: "ford., Barrie" },
  { title: "Gnawed", artist: "24thankyou" },
  { title: "the dealer", artist: "Nilüfer Yanya" },
  { title: "Little Man", artist: "Little Dragon" },
  { title: "metalmind", artist: "Kinji" },
  { title: "Automatic Love", artist: "Nourished by Time" },
  { title: "Orlando", artist: "Blood Orange" },
  { title: "Sleeping in", artist: "The Radio Dept." },
  { title: "Les Fleurs", artist: "Minnie Riperton" },
  { title: "Four Years and One Day", artist: "Mount Kimbie" },
  { title: "Summit Hill", artist: "Lutalo" },
  { title: "t", artist: "Dylan Thom" },
  { title: "halo", artist: "untitled" },
  { title: "Shooting Star", artist: "Hovvdy, runo plum" },
  { title: "Spangled", artist: "Fust" },
  { title: "Besties", artist: "Black Country, New Road" },
  { title: "together", artist: "NEW YORK" },
  { title: "Stone Femmes", artist: "Ydegirl" },
  { title: "Reality TV Argument Bleeds", artist: "Wednesday" },
  { title: "Anymore", artist: "Fade Evare" },
  { title: "I Come With Mud", artist: "Men I Trust" },
  { title: "for sale 2 own", artist: "Yot Club, Glitter Party" },
  { title: "u dont kno me", artist: "Yot Club" },
  { title: "1999 WILDFIRE", artist: "BROCKHAMPTON" },
  { title: "NO HALO", artist: "BROCKHAMPTON" },
  { title: "endless", artist: "Oklou" },
  { title: "Preludes", artist: "Flaer" },
  { title: "Getting Killed", artist: "Geese" },
  { title: "Exordium", artist: "Romeo + Juliet" },
  { title: "Tell my man", artist: "Operelly" },
  { title: "Far Cry", artist: "Resavoir" },
  { title: "Things We Do", artist: "Kaki King" },
  { title: "Le coeur en juillet", artist: "Isabelle" },
  { title: "Open", artist: "World Brain" },
  { title: "Di doo dah", artist: "Jane Birkin" },
  { title: "Perth", artist: "Bon Iver" },
  { title: "Dark Sun", artist: "h. pruz" },
  { title: "Come", artist: "h. pruz" },
  { title: "Marigold", artist: "snuggle" },
  { title: "Shortchanged", artist: "Snowy Band" },
  { title: "I could", artist: "Fine" },
  { title: "June Guitar", artist: "Alex G" },
  { title: "Poison Root", artist: "Alex G" },
  { title: "midori", artist: "mary in" },
  { title: "Bright Green Field", artist: "Squid" },
  { title: "Whatever the Weather II", artist: "Whatever The Weather" },
  { title: "Tires & Bookmarks", artist: "Teethe" },
  { title: "drive away", artist: "ps goner" },
  { title: "Reckoning", artist: "Taraneh, LUCY" },
  { title: "Poison Tree", artist: "Makeout Reef" },
  { title: "Susan", artist: "Bleary Eyed" },
  { title: "EVERYTHING I'VE EVER WANTED", artist: "Tiffany Day" },
  { title: "shelter in the cocoon", artist: "Witches Exist" },
  { title: "Dream of Jeannie - With the Light", artist: "Stina Nordenstam" },
  { title: "Whole", artist: "Basement" },
  { title: "A Quick One Before the Eternal Worm Devours Connecticut", artist: "Have A Nice Life" },
  { title: "Tina Fey", artist: "Worry Club" },
  { title: "Kiss the Ladder", artist: "Fleshwater" },
  { title: "Head Alight", artist: "Basement" },
  { title: "Are You The One", artist: "Basement" },
  { title: "simple things", artist: "runo plum" },
  { title: "Still Above", artist: "mark william lewis" },
  { title: "Dealerz", artist: "A Good Year, Quiet Light, Late Verlane" },
  { title: "I Got Heaven", artist: "Mannequin Pussy" },
  { title: "Okinawa Fantasia", artist: "Martin Glass" },
  { title: "Fallen Star", artist: "The Neighbourhood" },
  { title: "Teething", artist: "Ain't" },
  { title: "Grazer", artist: "Ain't" },
  { title: "I Don't Want To", artist: "voyeur" },
  { title: "meus passos", artist: "terraplana, shower curtain" },
  { title: "Duvet", artist: "bôa" },
  { title: "Pinch", artist: "CAN" },
  { title: "Angel", artist: "NewDad" },
  { title: "Kick The Curb", artist: "NewDad" },
  { title: "Room", artist: "Superheaven" },
  { title: "41", artist: "Retail Drugs" },
];

const skippedAmbiguous = [
  "Blue Desert",
  "Scrap and Love Songs Revisited",
  "It Was Only Perfect Because It Was Never Real",
  "System",
  "Suntub",
];

function normalize(value) {
  return String(value || "")
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function slug(value) {
  return normalize(value).replace(/\s+/g, "-").slice(0, 120) || "song";
}

function firstArtist(value) {
  return String(value || "")
    .split(",")[0]
    .trim();
}

function upgradedArtwork(url) {
  return String(url || "")
    .replace("100x100bb", "1000x1000bb")
    .replace("100x100", "1000x1000");
}

function canonicalArtwork(url) {
  return String(url || "")
    .replace(/\d+x\d+bb/, "1000x1000bb")
    .replace(/\d+x\d+/, "1000x1000");
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function durationString(ms) {
  if (!ms) return "";
  const total = Math.round(ms / 1000);
  const minutes = Math.floor(total / 60);
  const seconds = total % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

function scoreCandidate(item, requested) {
  const requestedTitle = normalize(requested.title);
  const requestedArtist = normalize(firstArtist(requested.artist));
  const itemTitle = normalize(item.trackName);
  const itemArtist = normalize(item.artistName);
  let score = 0;

  if (itemTitle === requestedTitle) score += 80;
  else if (itemTitle.includes(requestedTitle) || requestedTitle.includes(itemTitle)) score += 35;

  if (itemArtist === requestedArtist) score += 60;
  else if (itemArtist.includes(requestedArtist) || requestedArtist.includes(itemArtist)) score += 25;

  if (item.previewUrl) score += 10;
  if (item.artworkUrl100) score += 5;
  return score;
}

async function searchSong(requested) {
  const term = `${requested.title} ${requested.artist}`;
  const params = new URLSearchParams({
    term,
    media: "music",
    entity: "song",
    country: "US",
    limit: "10",
  });
  const url = `https://itunes.apple.com/search?${params.toString()}`;
  let response;
  for (let attempt = 0; attempt < 4; attempt += 1) {
    response = await fetch(url, {
      signal: AbortSignal.timeout(12000),
    });
    if (response.status !== 429) break;
    await sleep(1500 * (attempt + 1));
  }
  if (!response.ok) {
    throw new Error(`iTunes search failed ${response.status}`);
  }
  const data = await response.json();
  const candidates = (data.results || [])
    .filter((item) => item.wrapperType === "track" && item.kind === "song")
    .map((item) => ({ item, score: scoreCandidate(item, requested) }))
    .sort((a, b) => b.score - a.score);

  const best = candidates[0];
  if (!best || best.score < 70) return null;
  return best.item;
}

async function enrichAll() {
  const enriched = [];
  const skipped = [...skippedAmbiguous.map((label) => ({ label, reason: "ambiguous_no_artist" }))];
  const seenArtwork = new Set();
  const seenTrackIds = new Set();

  for (const requested of requestedSongs.slice(0, limit)) {
    try {
      await sleep(requestDelayMs);
      const match = await searchSong(requested);
      if (!match) {
        skipped.push({ label: `${requested.title} — ${requested.artist}`, reason: "no_confident_song_match" });
        continue;
      }

      const artwork = upgradedArtwork(match.artworkUrl100 || "");
      const artworkKey = canonicalArtwork(artwork);
      const trackId = String(match.trackId || "");
      if (!trackId || seenTrackIds.has(trackId)) {
        skipped.push({ label: `${requested.title} — ${requested.artist}`, reason: "duplicate_track" });
        continue;
      }
      if (!artworkKey || seenArtwork.has(artworkKey)) {
        skipped.push({ label: `${requested.title} — ${requested.artist}`, reason: "duplicate_album_art" });
        continue;
      }

      seenTrackIds.add(trackId);
      seenArtwork.add(artworkKey);
      enriched.push({
        id: trackId,
        title: match.trackName || requested.title,
        artist: match.artistName || firstArtist(requested.artist),
        albumArtURL: artwork,
        duration: durationString(match.trackTimeMillis),
        previewURL: match.previewUrl || null,
        appleMusicURL: match.trackViewUrl || null,
        spotifyURI: null,
        artistId: match.artistId ? String(match.artistId) : null,
        albumId: match.collectionId ? String(match.collectionId) : null,
        sourceTitle: requested.title,
        sourceArtist: requested.artist,
      });
    } catch (error) {
      skipped.push({
        label: `${requested.title} — ${requested.artist}`,
        reason: `lookup_error:${error.message}`,
      });
    }
  }

  return { enriched, skipped };
}

function cleanForFirestore(song, order) {
  const payload = {
    id: song.id,
    order,
    title: song.title,
    artist: song.artist,
    albumArtURL: song.albumArtURL,
    duration: song.duration,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    source: "seed-featured-songs",
    sourceTitle: song.sourceTitle,
    sourceArtist: song.sourceArtist,
  };
  for (const key of ["previewURL", "appleMusicURL", "spotifyURI", "artistId", "albumId"]) {
    if (song[key]) payload[key] = song[key];
  }
  return payload;
}

async function writeFeaturedSongs(songs) {
  admin.initializeApp({ projectId });
  const db = admin.firestore();

  // Replace the editorial collection so removed songs do not linger.
  const existing = await db.collection("featured_songs").listDocuments();
  for (let start = 0; start < existing.length; start += 450) {
    const batch = db.batch();
    existing.slice(start, start + 450).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }

  const batch = db.batch();
  songs.forEach((song, index) => {
    const docId = `${String(index + 1).padStart(4, "0")}-${slug(song.title)}-${song.id}`;
    batch.set(db.collection("featured_songs").doc(docId), cleanForFirestore(song, index + 1));
  });
  await batch.commit();
}

async function main() {
  const { enriched, skipped } = await enrichAll();
  console.log(
    JSON.stringify(
      {
        projectId,
        mode: shouldWrite ? "write" : "dry-run",
        requested: requestedSongs.length,
        enriched: enriched.length,
        skipped: skipped.length,
        skipped,
        preview: enriched.slice(0, 10).map((song, index) => ({
          order: index + 1,
          title: song.title,
          artist: song.artist,
          albumId: song.albumId,
        })),
      },
      null,
      2
    )
  );

  if (shouldWrite) {
    if (enriched.length < minimumWriteCount) {
      throw new Error(
        `Refusing to write only ${enriched.length} songs. Expected at least ${minimumWriteCount}; retry later or lower --minimum-write-count.`
      );
    }
    await writeFeaturedSongs(enriched);
    console.log(`Wrote ${enriched.length} featured_songs docs to ${projectId}.`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
