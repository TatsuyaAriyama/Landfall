import { deleteApp, initializeApp } from "firebase/app";
import {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  getAuth,
} from "firebase/auth";
import {
  arrayUnion,
  collection,
  connectFirestoreEmulator,
  doc,
  documentId,
  getDocs,
  getFirestore,
  limit,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from "firebase/firestore";

const projectId = process.env.GCLOUD_PROJECT || "demo-aftide";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;

if (!authHost || !firestoreHost) {
  throw new Error("Run through firebase emulators:exec with auth and firestore enabled.");
}

function emulatorAddress(host) {
  const [hostname, port] = host.split(":");
  return { hostname, port: Number(port) };
}

function testClient(name) {
  const app = initializeApp({ projectId, apiKey: "fake-api-key" }, name);
  const auth = getAuth(app);
  const firestore = getFirestore(app);
  connectAuthEmulator(auth, `http://${authHost}`, { disableWarnings: true });
  const address = emulatorAddress(firestoreHost);
  connectFirestoreEmulator(firestore, address.hostname, address.port);
  return { auth, firestore };
}

const owner = testClient("presence-owner");
const friend = testClient("presence-friend");
const stamp = Date.now();
const ownerCredential = await createUserWithEmailAndPassword(
  owner.auth,
  `presence-owner-${stamp}@example.test`,
  "Aftide-test-password-42",
);
const friendCredential = await createUserWithEmailAndPassword(
  friend.auth,
  `presence-friend-${stamp}@example.test`,
  "Aftide-test-password-42",
);
const ownerUid = ownerCredential.user.uid;
const friendUid = friendCredential.user.uid;
const roomId = "COST01";
const ownerRoom = doc(owner.firestore, "rooms", roomId);

await setDoc(ownerRoom, {
  name: "同期コスト確認",
  memberIds: [ownerUid],
  ownerUid,
  createdAt: serverTimestamp(),
});
await updateDoc(doc(friend.firestore, "rooms", roomId), {
  memberIds: arrayUnion(friendUid),
});

const presence = (firestore, uid) =>
  doc(firestore, "rooms", roomId, "presence", uid);
const presenceData = {
  x: 0,
  z: 0,
  yaw: 0,
  pose: "idle",
  aboard: true,
  sailX: 0,
  fishingRod: false,
  emoteSeq: 0,
  updatedAt: serverTimestamp(),
};
await setDoc(presence(owner.firestore, ownerUid), presenceData);
await setDoc(presence(friend.firestore, friendUid), presenceData);

const otherSailors = await getDocs(
  query(
    collection(owner.firestore, "rooms", roomId, "presence"),
    where(documentId(), "!=", ownerUid),
    limit(3),
  ),
);
if (otherSailors.size !== 1 || otherSailors.docs[0]?.id !== friendUid) {
  throw new Error(
    `Expected only the other sailor, received: ${otherSailors.docs
      .map((row) => row.id)
      .join(", ")}`,
  );
}

console.log("Presence query excludes the current sailor.");
await Promise.all([deleteApp(owner.auth.app), deleteApp(friend.auth.app)]);
