const projectId = process.env.GCLOUD_PROJECT || "demo-aftide";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;

if (!authHost || !firestoreHost) {
  throw new Error("Run through firebase emulators:exec with auth and firestore enabled.");
}

const authResponse = await fetch(
  `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
  {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      email: `color-rules-${Date.now()}@example.test`,
      password: "Aftide-test-password-42",
      returnSecureToken: true,
    }),
  },
);
const auth = await authResponse.json();
if (!authResponse.ok || !auth.localId || !auth.idToken) {
  throw new Error(`Could not create emulator user: ${JSON.stringify(auth)}`);
}

const itemDocument = (id) =>
  `http://${firestoreHost}/v1/projects/${projectId}/databases/(default)/documents/users/${auth.localId}/items/${id}`;

const itemBody = (styleToken) => ({
  fields: {
    name: { stringValue: "色ルール確認" },
    styleToken: { stringValue: styleToken },
    symbolToken: { stringValue: "anchor" },
    sortOrder: { integerValue: "0" },
    createdAt: { timestampValue: new Date().toISOString() },
    updatedAt: { timestampValue: new Date().toISOString() },
  },
});

async function writeItem(id, styleToken) {
  return fetch(itemDocument(id), {
    method: "PATCH",
    headers: {
      authorization: `Bearer ${auth.idToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(itemBody(styleToken)),
  });
}

const freeColor = await writeItem(
  "00000000-0000-4000-8000-000000000001",
  "sea-038-071-061",
);
if (!freeColor.ok) {
  throw new Error(`Valid free color was rejected: ${freeColor.status} ${await freeColor.text()}`);
}

const pccsColor = await writeItem(
  "00000000-0000-4000-8000-000000000002",
  "pccs-dkg-24",
);
if (!pccsColor.ok) {
  throw new Error(`Valid PCCS color was rejected: ${pccsColor.status} ${await pccsColor.text()}`);
}

const invalidColor = await writeItem(
  "00000000-0000-4000-8000-000000000003",
  "sea-999-999-999",
);
if (invalidColor.ok) {
  throw new Error("Malformed free color unexpectedly passed Firestore rules.");
}

console.log("Custom item color rules verified.");
