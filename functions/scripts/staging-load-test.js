#!/usr/bin/env node

const admin = require("firebase-admin");

function argNumber(name, fallback) {
  const prefix = `--${name}=`;
  const raw = process.argv.find((arg) => arg.startsWith(prefix));
  if (!raw) return fallback;
  const value = Number(raw.slice(prefix.length));
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : fallback;
}

const userCount = argNumber("users", 20);
const shareCount = argNumber("shares", 50);
const messageCount = argNumber("messages", 50);
const projectId = process.env.FIREBASE_PROJECT_ID;

if (!projectId) {
  console.error("Set FIREBASE_PROJECT_ID to a staging Firebase project.");
  process.exit(1);
}

admin.initializeApp({ projectId });
const db = admin.firestore();
const runId = `load-${Date.now()}`;

function userId(index) {
  return `${runId}-user-${index}`;
}

function conversationId(uidA, uidB) {
  return [uidA, uidB].sort().join("_");
}

async function main() {
  console.log(`Starting staging load smoke: ${runId}`);

  const batch = db.batch();
  for (let i = 0; i < userCount; i += 1) {
    const uid = userId(i);
    batch.set(db.collection("users").doc(uid), {
      username: `${runId}-u${i}`,
      firstName: `Load${i}`,
      lastName: "Test",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    batch.set(db.collection("users").doc(uid).collection("private").doc("profile"), {
      phone: `+1555${String(i).padStart(7, "0")}`,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  let writes = 0;
  for (let i = 0; i < shareCount; i += 1) {
    const sender = userId(i % userCount);
    const recipient = userId((i + 1) % userCount);
    await db.collection("shares").doc(`${runId}-share-${i}`).set({
      senderId: sender,
      recipientId: recipient,
      recipientUsername: `${runId}-u${(i + 1) % userCount}`,
      note: i % 3 === 0 ? "load test" : null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      song: {
        id: `song-${i % 10}`,
        title: `Load Song ${i % 10}`,
        artist: "Load Artist",
        albumArtURL: "",
        duration: "",
        spotifyURI: null,
        previewURL: null,
        appleMusicURL: null,
      },
      sender: { id: sender, firstName: "Load", lastName: "Sender", username: sender },
      recipient: { id: recipient, firstName: "Load", lastName: "Recipient", username: recipient },
    });
    writes += 1;
  }

  for (let i = 0; i < messageCount; i += 1) {
    const sender = userId(i % userCount);
    const recipient = userId((i + 1) % userCount);
    const convId = conversationId(sender, recipient);
    const convRef = db.collection("conversations").doc(convId);
    await convRef.set(
      {
        participants: [sender, recipient].sort(),
        participantNames: { [sender]: sender, [recipient]: recipient },
        lastMessageText: `Load message ${i}`,
        lastMessageTimestamp: admin.firestore.FieldValue.serverTimestamp(),
        [`unreadCount_${sender}`]: 0,
        [`unreadCount_${recipient}`]: admin.firestore.FieldValue.increment(1),
      },
      { merge: true }
    );
    await convRef.collection("messages").doc(`${runId}-msg-${i}`).set({
      senderId: sender,
      text: `Load message ${i}`,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    writes += 2;
  }

  const shareRead = await db
    .collection("shares")
    .where("recipientId", "==", userId(1))
    .orderBy("timestamp", "desc")
    .limit(10)
    .get();

  const convoRead = await db
    .collection("conversations")
    .where("participants", "array-contains", userId(1))
    .orderBy("lastMessageTimestamp", "desc")
    .limit(10)
    .get();

  console.log(
    JSON.stringify({
      runId,
      users: userCount,
      writes,
      shareReadCount: shareRead.size,
      conversationReadCount: convoRead.size,
    })
  );
}

main().catch((err) => {
  console.error("staging load smoke failed:", err);
  process.exit(1);
});
