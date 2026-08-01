import { createHash, randomBytes } from "node:crypto";
import {
  Environment,
  SignedDataVerifier,
  type JWSTransactionDecodedPayload,
} from "@apple/app-store-server-library";
import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { defineSecret, defineString } from "firebase-functions/params";
import * as functionsV1 from "firebase-functions/v1";
import Stripe from "stripe";
import { appleRootCertificates } from "./appleRootCertificates";

if (getApps().length === 0) initializeApp();

const db = getFirestore();
const stripeRestrictedKey = defineSecret("STRIPE_RESTRICTED_KEY");
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");
const voyagePassPriceId = defineString("STRIPE_VOYAGE_PASS_PRICE_ID");
const publicWebUrl = defineString("PUBLIC_WEB_URL", {
  default: "https://aftide.app",
});

const REGION = "asia-northeast1";
const VOYAGE_PASS_ENTITLEMENT = "voyagePass";
const APP_STORE_VOYAGE_PASS_ENTITLEMENT = "voyagePassAppStore";
const APP_STORE_BUNDLE_ID = "com.tatsuyaariyama.Landfall";
const APP_STORE_APP_APPLE_ID = 6791381131;
const APP_STORE_PRODUCT_IDS = new Set([
  "com.tatsuyaariyama.keelmira.voyagepass.monthly",
  "com.tatsuyaariyama.keelmira.voyagepass.annual",
]);
const DEVELOPER_EMAIL = "ari.initx@gmail.com";
const CHECKOUT_IDENTIFIER = "keelmira_web_seawinds";
const PUBLIC_HARBORS = ["language", "certification", "student", "reading", "making"];

function stripeClient() {
  return new Stripe(stripeRestrictedKey.value(), {
    apiVersion: "2026-06-24.dahlia",
    appInfo: {
      name: "KeelMira Voyage Pass",
      version: "1.0.0",
    },
  });
}

function requireUid(auth: { uid: string } | undefined): string {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in before managing a Voyage Pass.");
  return auth.uid;
}

function isDeveloper(auth: { token: Record<string, unknown> } | undefined): boolean {
  return auth?.token.email === DEVELOPER_EMAIL && auth.token.email_verified === true;
}

function appAccountTokenFor(uid: string): string {
  const bytes = createHash("sha256").update(uid, "utf8").digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

const productionTransactionVerifier = new SignedDataVerifier(
  appleRootCertificates,
  true,
  Environment.PRODUCTION,
  APP_STORE_BUNDLE_ID,
  APP_STORE_APP_APPLE_ID,
);
const sandboxTransactionVerifier = new SignedDataVerifier(
  appleRootCertificates,
  true,
  Environment.SANDBOX,
  APP_STORE_BUNDLE_ID,
);

async function verifyAppStoreTransaction(
  signedTransaction: string,
): Promise<JWSTransactionDecodedPayload> {
  try {
    return await productionTransactionVerifier.verifyAndDecodeTransaction(signedTransaction);
  } catch {
    try {
      // TestFlightとStoreKit SandboxはSandbox署名。本番検証失敗後だけ試す。
      return await sandboxTransactionVerifier.verifyAndDecodeTransaction(signedTransaction);
    } catch {
      throw new HttpsError("permission-denied", "The App Store transaction could not be verified.");
    }
  }
}

/**
 * iOSのStoreKit 2 JWSをApple公式ライブラリで再検証し、
 * Firestoreルールが参照する期限付き航海証を発行する。
 */
export const syncAppStoreVoyagePass = onCall(
  { region: REGION },
  async (request) => {
    const uid = requireUid(request.auth);
    if (isDeveloper(request.auth)) return { active: true, developer: true };

    const signedTransaction = request.data?.signedTransaction;
    if (typeof signedTransaction !== "string" || signedTransaction.length < 100 || signedTransaction.length > 30_000) {
      throw new HttpsError("invalid-argument", "A signed App Store transaction is required.");
    }

    const transaction = await verifyAppStoreTransaction(signedTransaction);
    if (!transaction.productId || !APP_STORE_PRODUCT_IDS.has(transaction.productId)) {
      throw new HttpsError("permission-denied", "This product is not a Voyage Pass.");
    }
    if (
      typeof transaction.expiresDate !== "number" ||
      transaction.expiresDate <= Date.now() ||
      transaction.revocationDate !== undefined
    ) {
      throw new HttpsError("failed-precondition", "This Voyage Pass is no longer active.");
    }
    if (
      typeof transaction.appAccountToken !== "string" ||
      transaction.appAccountToken.toLowerCase() !== appAccountTokenFor(uid)
    ) {
      throw new HttpsError("permission-denied", "This Voyage Pass belongs to another account.");
    }
    if (!transaction.transactionId || !transaction.originalTransactionId) {
      throw new HttpsError("permission-denied", "The App Store transaction is incomplete.");
    }

    const currentPeriodEnd = Timestamp.fromMillis(transaction.expiresDate);
    await db.doc(`users/${uid}/entitlements/${APP_STORE_VOYAGE_PASS_ENTITLEMENT}`).set({
      active: true,
      status: "active",
      source: "appStore",
      productId: transaction.productId,
      transactionId: transaction.transactionId,
      originalTransactionId: transaction.originalTransactionId,
      environment: transaction.environment ?? null,
      currentPeriodEnd,
      updatedAt: Timestamp.now(),
    });

    return {
      active: true,
      currentPeriodEnd: currentPeriodEnd.toMillis(),
    };
  },
);

function returnUrl(path = ""): string {
  const base = new URL(publicWebUrl.value());
  if (base.protocol !== "https:") {
    throw new Error("PUBLIC_WEB_URL must use HTTPS.");
  }
  return new URL(path || "/", `${base.origin}/`).toString();
}

function randomLetterSuffix(length = 8): string {
  const alphabet = "abcdefghijklmnopqrstuvwxyz";
  return Array.from(
    randomBytes(length),
    (byte) => alphabet[byte % alphabet.length],
  ).join("");
}

async function enforceBillingCooldown(
  uid: string,
  field: "lastCheckoutAt" | "lastPortalAt",
): Promise<void> {
  const ref = db.collection("billingCustomers").doc(uid);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const last = snapshot.get(field);
    const now = Timestamp.now();
    if (last instanceof Timestamp && now.toMillis() - last.toMillis() < 5_000) {
      throw new HttpsError(
        "resource-exhausted",
        "Please wait a moment before trying again.",
      );
    }
    transaction.set(ref, { [field]: now, updatedAt: now }, { merge: true });
  });
}

async function customerIdFor(
  stripe: Stripe,
  uid: string,
  email?: string,
): Promise<string> {
  const ref = db.collection("billingCustomers").doc(uid);
  const snapshot = await ref.get();
  const existing = snapshot.get("stripeCustomerId");
  if (typeof existing === "string" && existing.startsWith("cus_")) return existing;

  const customer = await stripe.customers.create(
    {
      email,
      metadata: { firebaseUid: uid },
      name: "KeelMira navigator",
    },
    { idempotencyKey: `keelmira-customer-${uid}` },
  );

  await ref.set(
    {
      stripeCustomerId: customer.id,
      updatedAt: Timestamp.now(),
    },
    { merge: true },
  );
  return customer.id;
}

async function existingPassPortalUrl(
  stripe: Stripe,
  customer: string,
): Promise<string | null> {
  const subscriptions = await stripe.subscriptions.list({
    customer,
    status: "all",
    limit: 10,
  });
  const manageable = subscriptions.data.some(
    (subscription) =>
      subscription.status !== "canceled" &&
      subscription.status !== "incomplete_expired",
  );
  if (!manageable) return null;
  const portal = await stripe.billingPortal.sessions.create({
    customer,
    return_url: returnUrl("/?voyage-pass=portal-return"),
  });
  return portal.url;
}

export const createVoyagePassCheckout = onCall(
  {
    region: REGION,
    secrets: [stripeRestrictedKey],
  },
  async (request) => {
    const uid = requireUid(request.auth);
    await enforceBillingCooldown(uid, "lastCheckoutAt");
    const stripe = stripeClient();
    const customer = await customerIdFor(stripe, uid, request.auth?.token.email as string | undefined);
    const existingPortal = await existingPassPortalUrl(stripe, customer);
    if (existingPortal) return { url: existingPortal };
    const integrationSuffix = randomLetterSuffix();

    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer,
      client_reference_id: uid,
      line_items: [{ price: voyagePassPriceId.value(), quantity: 1 }],
      metadata: {
        firebaseUid: uid,
        entitlement: VOYAGE_PASS_ENTITLEMENT,
      },
      subscription_data: {
        metadata: {
          firebaseUid: uid,
          entitlement: VOYAGE_PASS_ENTITLEMENT,
        },
      },
      success_url: returnUrl("/?voyage-pass=success"),
      cancel_url: returnUrl("/?voyage-pass=cancelled"),
      integration_identifier: `${CHECKOUT_IDENTIFIER}_${integrationSuffix}`,
    });

    if (!session.url) throw new HttpsError("internal", "Stripe did not return a Checkout URL.");
    return { url: session.url };
  },
);

export const createVoyagePassPortal = onCall(
  {
    region: REGION,
    secrets: [stripeRestrictedKey],
  },
  async (request) => {
    const uid = requireUid(request.auth);
    await enforceBillingCooldown(uid, "lastPortalAt");
    const customerSnapshot = await db.collection("billingCustomers").doc(uid).get();
    const customer = customerSnapshot.get("stripeCustomerId");
    if (typeof customer !== "string") {
      throw new HttpsError("failed-precondition", "No Voyage Pass billing profile exists.");
    }

    const session = await stripeClient().billingPortal.sessions.create({
      customer,
      return_url: returnUrl("/?voyage-pass=portal-return"),
    });
    return { url: session.url };
  },
);

function uidFromSubscription(subscription: Stripe.Subscription): string | null {
  const uid = subscription.metadata.firebaseUid;
  return typeof uid === "string" && uid.length > 0 ? uid : null;
}

function subscriptionAccess(status: Stripe.Subscription.Status): boolean {
  return status === "active" || status === "trialing" || status === "past_due";
}

function subscriptionPeriodEnd(subscription: Stripe.Subscription): Timestamp | null {
  const ends = subscription.items.data
    .map((item) => item.current_period_end)
    .filter((value): value is number => typeof value === "number");
  return ends.length > 0 ? Timestamp.fromMillis(Math.max(...ends) * 1000) : null;
}

async function entitlementWrite(
  batch: FirebaseFirestore.WriteBatch,
  subscription: Stripe.Subscription,
): Promise<void> {
  const uid = uidFromSubscription(subscription);
  if (!uid) throw new Error(`Subscription ${subscription.id} is missing firebaseUid metadata.`);

  const item = subscription.items.data[0];
  const productId =
    typeof item?.price.product === "string" ? item.price.product : item?.price.product?.id;
  const periodEnd = subscriptionPeriodEnd(subscription);

  batch.set(
    db.doc(`users/${uid}/entitlements/${VOYAGE_PASS_ENTITLEMENT}`),
    {
      active: subscriptionAccess(subscription.status),
      status: subscription.status,
      stripeSubscriptionId: subscription.id,
      productId: productId ?? null,
      priceId: item?.price.id ?? null,
      currentPeriodEnd: periodEnd,
      cancelAtPeriodEnd: subscription.cancel_at_period_end,
      updatedAt: Timestamp.now(),
    },
    { merge: true },
  );
}

async function subscriptionFromCheckout(
  stripe: Stripe,
  session: Stripe.Checkout.Session,
): Promise<Stripe.Subscription | null> {
  const id =
    typeof session.subscription === "string"
      ? session.subscription
      : session.subscription?.id;
  return id ? stripe.subscriptions.retrieve(id) : null;
}

export const stripeWebhook = onRequest(
  {
    region: REGION,
    secrets: [stripeRestrictedKey, stripeWebhookSecret],
  },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).send("Method not allowed");
      return;
    }

    const signature = request.header("stripe-signature");
    if (!signature) {
      response.status(400).send("Missing Stripe signature");
      return;
    }

    let event: Stripe.Event;
    try {
      event = stripeClient().webhooks.constructEvent(
        request.rawBody,
        signature,
        stripeWebhookSecret.value(),
      );
    } catch {
      response.status(400).send("Invalid Stripe signature");
      return;
    }

    const eventRef = db.collection("stripeEvents").doc(event.id);
    if ((await eventRef.get()).exists) {
      response.status(200).send("Already processed");
      return;
    }

    try {
      const batch = db.batch();
      if (
        event.type === "customer.subscription.created" ||
        event.type === "customer.subscription.updated" ||
        event.type === "customer.subscription.deleted"
      ) {
        await entitlementWrite(batch, event.data.object);
      } else if (event.type === "checkout.session.completed") {
        const subscription = await subscriptionFromCheckout(
          stripeClient(),
          event.data.object,
        );
        if (subscription) await entitlementWrite(batch, subscription);
      }

      batch.create(eventRef, {
        type: event.type,
        processedAt: Timestamp.now(),
      });
      await batch.commit();
      response.status(200).send("Processed");
    } catch (error) {
      const code =
        typeof error === "object" && error !== null && "code" in error
          ? String(error.code)
          : "";
      if (code === "6" || code === "already-exists") {
        response.status(200).send("Already processed");
        return;
      }
      console.error("Stripe webhook processing failed", {
        eventId: event.id,
        eventType: event.type,
      });
      response.status(500).send("Webhook processing failed");
    }
  },
);

async function deleteDocuments(
  documents: FirebaseFirestore.QueryDocumentSnapshot[],
): Promise<void> {
  if (documents.length === 0) return;
  const writer = db.bulkWriter();
  for (const document of documents) writer.delete(document.ref);
  await writer.close();
}

async function deleteSharedUserContent(uid: string): Promise<void> {
  // 現在参加中のルームから、カード・月間記録・共同航海の準備を消して退室させる。
  const rooms = await db.collection("rooms")
    .where("memberIds", "array-contains", uid)
    .get();
  for (const room of rooms.docs) {
    const sessions = await room.ref.collection("crewSessions").get();
    await Promise.all(
      sessions.docs.map((session) =>
        session.ref.collection("plans").doc(uid).delete().catch(() => undefined),
      ),
    );
    await db.recursiveDelete(room.ref.collection("members").doc(uid));
    await room.ref.update({ memberIds: FieldValue.arrayRemove(uid) });
  }

  // 退室済みの過去ルームに残る発言も、アカウント削除時には消す。
  const chat = await db.collectionGroup("chat").where("uid", "==", uid).get();
  await deleteDocuments(chat.docs);

  // 旧クライアントがuidフィールドを持たずに作ったplanも文書IDで拾う。
  const legacyPlans = await db.collectionGroup("plans").get();
  await deleteDocuments(legacyPlans.docs.filter((plan) => plan.id === uid));

  for (const slug of PUBLIC_HARBORS) {
    await db.recursiveDelete(
      db.doc(`publicHarbors/${slug}/members/${uid}`),
    );
  }

  // users/{uid} 自体が無くても、全サブコレクションを再帰削除する。
  await db.recursiveDelete(db.doc(`users/${uid}`));
}

// Firebaseアカウント削除後に、課金・共有UGC・私的バックアップを管理SDKで
// 再度片付ける。クライアント側削除が通信断で途中になっても、このトリガーが完遂する。
export const cleanupVoyagePassOnUserDelete = functionsV1
  .region(REGION)
  .runWith({
    secrets: ["STRIPE_RESTRICTED_KEY"],
    failurePolicy: true,
    timeoutSeconds: 540,
    memory: "512MB",
  })
  .auth.user()
  .onDelete(async (user) => {
    const customerRef = db.collection("billingCustomers").doc(user.uid);
    const customer = (await customerRef.get()).get("stripeCustomerId");
    if (typeof customer === "string") {
      const stripe = stripeClient();
      const subscriptions = await stripe.subscriptions.list({
        customer,
        status: "all",
        limit: 100,
      });
      await Promise.all(
        subscriptions.data
          .filter(
            (subscription) =>
              subscription.status !== "canceled" &&
              subscription.status !== "incomplete_expired",
          )
          .map((subscription) => stripe.subscriptions.cancel(subscription.id)),
      );
    }

    await deleteSharedUserContent(user.uid);
    await customerRef.delete();
  });
