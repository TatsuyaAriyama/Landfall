import { createHash, randomBytes } from "node:crypto";
import {
  Environment,
  SignedDataVerifier,
  type JWSTransactionDecodedPayload,
} from "@apple/app-store-server-library";
import { getApps, initializeApp } from "firebase-admin/app";
import { FieldPath, FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { defineSecret, defineString } from "firebase-functions/params";
import * as functionsV1 from "firebase-functions/v1";
import sharp from "sharp";
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
const FEEDBACK_CATEGORIES = new Set(["idea", "issue", "design", "other"]);
const PUBLIC_JOURNAL_BODY_LIMIT = 260;
const PUBLIC_JOURNAL_INPUT_BYTES = 1_500_000;
const PUBLIC_JOURNAL_STORED_BYTES = 700_000;
const PUBLIC_JOURNAL_INPUT_PIXELS = 8_000_000;
const PUBLIC_JOURNAL_PUBLISH_COOLDOWN_MS = 10_000;
const PUBLIC_JOURNAL_PUBLISH_HOURLY_LIMIT = 12;
const PUBLIC_JOURNAL_GRAPHEME_SEGMENTER = new Intl.Segmenter("und", {
  granularity: "grapheme",
});
const PUBLIC_JOURNAL_STYLE_TOKENS = new Set([
  "midnight",
  "coral",
  "ink",
  "seaGreen",
  "violet",
  "sunYellow",
  "harbor",
  "sand",
  "ember",
  "rust",
  "lavender",
  "sunrise",
]);
const PUBLIC_JOURNAL_SYMBOL_TOKENS = new Set([
  "anchor",
  "compass",
  "wheel",
  "lighthouse",
  "island",
  "phoenix",
  "book",
  "pen",
  "sailboat",
  "attire",
]);
const PUBLIC_CONTENT_REPORT_REASONS = new Set([
  "inappropriate",
  "harassment",
  "privacy",
  "spam",
  "profile",
]);
const PRIVATE_ISLAND_CODE = /^[A-HJ-NP-Z2-9]{6}$/;
const PRIVATE_ISLAND_MESSAGE_ID =
  /^(?:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}|[A-Za-z0-9]{20})$/;
const PRIVATE_ISLAND_CHAT_LIMIT = 500;
const PRIVATE_ISLAND_CHAT_COOLDOWN_MS = 750;
const PRIVATE_ISLAND_CHAT_HOURLY_LIMIT = 120;
const PRIVATE_ISLAND_REPORT_DAILY_LIMIT = 20;
const PUBLIC_HARBOR_MONTH_SESSIONS_LIMIT = 1_000;
const PUBLIC_HARBOR_MONTH_INPUT_BYTES = 800_000;
const PUBLIC_HARBOR_MONTH_HOURLY_LIMIT = 300;

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

function requiredFeedbackString(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length < minimum || trimmed.length > maximum) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must be between ${minimum} and ${maximum} characters.`,
    );
  }
  return trimmed;
}

function publicJournalDayId(date = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Tokyo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const value = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((part) => part.type === type)?.value ?? "";
  return `${value("year")}-${value("month")}-${value("day")}`;
}

function isUnicodeControl(character: string, preserveTextWhitespace: boolean): boolean {
  const codePoint = character.codePointAt(0) ?? 0;
  if (preserveTextWhitespace && (codePoint === 9 || codePoint === 10 || codePoint === 13)) {
    return false;
  }
  const isC0OrC1 = codePoint <= 31 || (codePoint >= 127 && codePoint <= 159);
  return isC0OrC1 || /[\p{Cf}\p{Cs}]/u.test(character);
}

function withoutUnicodeControls(value: string, preserveTextWhitespace: boolean): string {
  return Array.from(value)
    .filter((character) => !isUnicodeControl(character, preserveTextWhitespace))
    .join("");
}

function publicJournalText(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "body must be a string.");
  }
  const normalized = withoutUnicodeControls(value.normalize("NFC"), true).trim();
  const graphemeCount = Array.from(
    PUBLIC_JOURNAL_GRAPHEME_SEGMENTER.segment(normalized),
  ).length;
  if (graphemeCount < 1 || graphemeCount > PUBLIC_JOURNAL_BODY_LIMIT) {
    throw new HttpsError(
      "invalid-argument",
      `body must be between 1 and ${PUBLIC_JOURNAL_BODY_LIMIT} characters.`,
    );
  }
  const compact = normalized.toLocaleLowerCase("ja").replace(/[\s._-]+/gu, "");
  const prohibited = [
    "killyourself",
    "nigger",
    "faggot",
    "死ね",
    "しね",
    "殺す",
    "ころす",
    "自殺しろ",
  ];
  if (prohibited.some((phrase) => compact.includes(phrase))) {
    throw new HttpsError("invalid-argument", "body cannot be published.");
  }
  return normalized;
}

function publicJournalMemberString(value: unknown, fallback: string, maximum: number): string {
  if (typeof value !== "string") return fallback;
  const trimmed = withoutUnicodeControls(value.normalize("NFC"), false).trim();
  return trimmed.length > 0 ? Array.from(trimmed).slice(0, maximum).join("") : fallback;
}

function publicJournalToken(
  value: unknown,
  allowed: Set<string>,
  fallback: string,
): string {
  if (typeof value !== "string") return fallback;
  const token = withoutUnicodeControls(value.normalize("NFC"), false).trim();
  return allowed.has(token) ? token : fallback;
}

function publicJournalSymbolToken(value: unknown): string {
  if (typeof value === "string") {
    switch (withoutUnicodeControls(value.normalize("NFC"), false).trim()) {
      case "wave": return "anchor";
      case "comet": return "compass";
      case "sun": return "lighthouse";
      default: break;
    }
  }
  return publicJournalToken(value, PUBLIC_JOURNAL_SYMBOL_TOKENS, "phoenix");
}

function reportSnapshotString(value: unknown, maximum: number): string | null {
  if (typeof value !== "string") return null;
  return Array.from(value.normalize("NFC")).slice(0, maximum).join("");
}

function privateIslandCode(value: unknown): string {
  const code = typeof value === "string" ? value.trim().toUpperCase() : "";
  if (!PRIVATE_ISLAND_CODE.test(code)) {
    throw new HttpsError("invalid-argument", "A valid invite code is required.");
  }
  return code;
}

function privateIslandMessageId(value: unknown): string {
  const messageId = typeof value === "string" ? value.trim() : "";
  if (!PRIVATE_ISLAND_MESSAGE_ID.test(messageId)) {
    throw new HttpsError("invalid-argument", "A valid message identifier is required.");
  }
  return messageId;
}

function privateIslandChatText(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "text must be a string.");
  }
  const text = withoutUnicodeControls(value.normalize("NFC"), true).trim();
  const characters = Array.from(text);
  if (characters.length < 1 || characters.length > PRIVATE_ISLAND_CHAT_LIMIT) {
    throw new HttpsError(
      "invalid-argument",
      `text must be between 1 and ${PRIVATE_ISLAND_CHAT_LIMIT} characters.`,
    );
  }
  const compact = text.toLocaleLowerCase("ja").replace(/[\s._-]+/gu, "");
  const prohibited = [
    "killyourself",
    "kys",
    "nigger",
    "faggot",
    "死ね",
    "しね",
    "殺す",
    "ころす",
    "自殺しろ",
  ];
  if (prohibited.some((phrase) => compact.includes(phrase))) {
    throw new HttpsError("invalid-argument", "text cannot be sent.");
  }
  return text;
}

function plainRecord(value: unknown): Record<string, unknown> | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function boundedPublicString(
  value: unknown,
  maximum: number,
  preserveTextWhitespace = false,
): string | null {
  if (typeof value !== "string") return null;
  const normalized = withoutUnicodeControls(value.normalize("NFC"), preserveTextWhitespace);
  return Array.from(normalized).slice(0, maximum).join("");
}

function validMonthIds(now = new Date()): Set<string> {
  // A local calendar can be one day ahead of or behind UTC. Accepting the
  // adjacent instants covers every iOS time zone without opening arbitrary
  // historical document IDs to a modified client.
  return new Set([-86_400_000, 0, 86_400_000].map((offset) =>
    new Date(now.getTime() + offset).toISOString().slice(0, 7)));
}

function publicHarborMonthPayload(value: unknown, maximumDay: number): {
  days: number[];
  sessions: Record<string, unknown>[];
} {
  const input = plainRecord(value);
  if (!input || !Array.isArray(input.days) || !Array.isArray(input.sessions)) {
    throw new HttpsError("invalid-argument", "A valid month payload is required.");
  }
  if (input.days.length > 31 || input.sessions.length > PUBLIC_HARBOR_MONTH_SESSIONS_LIMIT) {
    throw new HttpsError("invalid-argument", "The month payload is too large.");
  }

  const days = input.days.map((day) => {
    if (typeof day !== "number" || !Number.isSafeInteger(day) || day < 1 || day > maximumDay) {
      throw new HttpsError("invalid-argument", "A study day is outside the selected month.");
    }
    return day;
  });
  if (new Set(days).size !== days.length) {
    throw new HttpsError("invalid-argument", "Study days cannot be duplicated.");
  }

  const now = Date.now();
  const sessions = input.sessions.map((raw) => {
    const session = plainRecord(raw);
    if (!session) throw new HttpsError("invalid-argument", "Every session must be an object.");
    const allowedKeys = new Set([
      "day", "minutes", "dateMilliseconds", "note", "itemName", "styleToken", "symbolToken",
    ]);
    if (Object.keys(session).some((key) => !allowedKeys.has(key))) {
      throw new HttpsError("invalid-argument", "A session contains an unknown field.");
    }
    const day = session.day;
    const minutes = session.minutes;
    const dateMilliseconds = session.dateMilliseconds;
    if (typeof day !== "number" || !Number.isSafeInteger(day) || day < 1 || day > maximumDay) {
      throw new HttpsError("invalid-argument", "A session day is invalid.");
    }
    if (
      typeof minutes !== "number" || !Number.isSafeInteger(minutes) ||
      minutes < 1 || minutes > 6_000
    ) {
      throw new HttpsError("invalid-argument", "A session duration is invalid.");
    }
    if (
      typeof dateMilliseconds !== "number" || !Number.isSafeInteger(dateMilliseconds) ||
      dateMilliseconds < 946_684_800_000 || dateMilliseconds > now + 10 * 60 * 1_000
    ) {
      throw new HttpsError("invalid-argument", "A session date is invalid.");
    }

    const output: Record<string, unknown> = {
      day,
      minutes,
      date: Timestamp.fromMillis(dateMilliseconds),
    };
    const note = boundedPublicString(session.note, 500, true);
    const itemName = boundedPublicString(session.itemName, 60);
    if (note) output.note = note;
    if (itemName) output.itemName = itemName;
    if (session.styleToken !== undefined) {
      if (typeof session.styleToken !== "string" || !PUBLIC_JOURNAL_STYLE_TOKENS.has(session.styleToken)) {
        throw new HttpsError("invalid-argument", "A session style is invalid.");
      }
      output.styleToken = session.styleToken;
    }
    if (session.symbolToken !== undefined) {
      if (typeof session.symbolToken !== "string" || !PUBLIC_JOURNAL_SYMBOL_TOKENS.has(session.symbolToken)) {
        throw new HttpsError("invalid-argument", "A session symbol is invalid.");
      }
      output.symbolToken = session.symbolToken;
    }
    return output;
  });

  if (Buffer.byteLength(JSON.stringify({ days, sessions }), "utf8") > PUBLIC_HARBOR_MONTH_INPUT_BYTES) {
    throw new HttpsError("invalid-argument", "The month payload exceeds the storage limit.");
  }
  return { days: [...days].sort((left, right) => left - right), sessions };
}

function privateIslandMemberData(value: unknown, joinedAt: Timestamp): Record<string, unknown> {
  const input = plainRecord(value) ?? {};
  const displayName = boundedPublicString(input.displayName, 60)?.trim() || "Sailor";
  const styleToken = typeof input.styleToken === "string" && PUBLIC_JOURNAL_STYLE_TOKENS.has(input.styleToken)
    ? input.styleToken
    : "midnight";
  const symbolToken = typeof input.symbolToken === "string" && PUBLIC_JOURNAL_SYMBOL_TOKENS.has(input.symbolToken)
    ? input.symbolToken
    : "phoenix";
  const output: Record<string, unknown> = {
    displayName,
    styleToken,
    symbolToken,
    resolve: boundedPublicString(input.resolve, 80)?.trim() ?? "",
    boatSail: boundedPublicString(input.boatSail, 24) || "sand",
    boatJib: boundedPublicString(input.boatJib, 24) || "sand",
    boatHull: boundedPublicString(input.boatHull, 24) || "starter",
    boatStripe: boundedPublicString(input.boatStripe, 24) || "none",
    boatFlag: boundedPublicString(input.boatFlag, 24) || "none",
    joinedAt,
  };
  if (typeof input.sinceDay === "string" && /^\d{4}-\d{2}-\d{2}$/u.test(input.sinceDay)) {
    output.sinceDay = input.sinceDay;
  }
  return output;
}

function hashedActorId(namespace: string, actor: string): string {
  return createHash("sha256").update(`${namespace}:${actor}`, "utf8").digest("hex");
}

function publicJournalRateLimitId(uid: string): string {
  return createHash("sha256").update(`uid:${uid}`, "utf8").digest("hex");
}

async function enforcePublicJournalPublishRateLimit(
  uid: string,
  requestId: string,
): Promise<void> {
  const rateLimitRef = db.collection("publicJournalPublishRateLimits")
    .doc(publicJournalRateLimitId(uid));
  const now = Timestamp.now();

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(rateLimitRef);
    const windowStartedAt = snapshot.get("windowStartedAt");
    const lastAttemptAt = snapshot.get("lastAttemptAt");
    const storedCount = snapshot.get("count");
    const lastRequestId = snapshot.get("lastRequestId");
    const storedSameRequestCount = snapshot.get("sameRequestCount");
    const sameWindow =
      windowStartedAt instanceof Timestamp &&
      now.toMillis() - windowStartedAt.toMillis() < 60 * 60 * 1_000;
    const nextCount = sameWindow && typeof storedCount === "number" ? storedCount + 1 : 1;
    if (nextCount > PUBLIC_JOURNAL_PUBLISH_HOURLY_LIMIT) {
      throw new HttpsError("resource-exhausted", "The hourly publishing limit has been reached.");
    }

    const sameRequest = lastRequestId === requestId;
    const nextSameRequestCount = sameRequest && typeof storedSameRequestCount === "number"
      ? storedSameRequestCount + 1
      : 1;
    if (
      lastAttemptAt instanceof Timestamp &&
      now.toMillis() - lastAttemptAt.toMillis() < PUBLIC_JOURNAL_PUBLISH_COOLDOWN_MS &&
      (!sameRequest || nextSameRequestCount > 2)
    ) {
      throw new HttpsError("resource-exhausted", "Please wait before publishing again.");
    }

    transaction.set(rateLimitRef, {
      count: nextCount,
      windowStartedAt: sameWindow ? windowStartedAt : now,
      lastAttemptAt: now,
      lastRequestId: requestId,
      sameRequestCount: nextSameRequestCount,
      updatedAt: now,
    });
  });
}

async function preparePublicJournalPhoto(imageBase64: unknown): Promise<{
  data: Buffer;
  width: number;
  height: number;
}> {
  if (
    typeof imageBase64 !== "string" ||
    imageBase64.length < 16 ||
    imageBase64.length > Math.ceil(PUBLIC_JOURNAL_INPUT_BYTES * 4 / 3) + 8 ||
    !/^[A-Za-z0-9+/]+={0,2}$/u.test(imageBase64)
  ) {
    throw new HttpsError("invalid-argument", "A valid JPEG photo is required.");
  }
  const input = Buffer.from(imageBase64, "base64");
  if (input.length < 16 || input.length > PUBLIC_JOURNAL_INPUT_BYTES) {
    throw new HttpsError("invalid-argument", "The photo is too large.");
  }

  try {
    const metadata = await sharp(input, {
      animated: false,
      failOn: "warning",
      limitInputPixels: PUBLIC_JOURNAL_INPUT_PIXELS,
    }).metadata();
    if (metadata.format !== "jpeg" || (metadata.pages ?? 1) !== 1) {
      throw new HttpsError("invalid-argument", "Only a single JPEG photo is supported.");
    }

    const attempts = [
      { size: 1_600, quality: 80 },
      { size: 1_200, quality: 65 },
    ];
    for (const attempt of attempts) {
      const result = await sharp(input, {
        animated: false,
        failOn: "warning",
        limitInputPixels: PUBLIC_JOURNAL_INPUT_PIXELS,
      })
        .rotate()
        .resize({
          width: attempt.size,
          height: attempt.size,
          fit: "inside",
          withoutEnlargement: true,
        })
        // withMetadata()を呼ばず、EXIF・GPS・元ファイル情報を公開画像へ持ち込まない。
        .jpeg({ quality: attempt.quality, mozjpeg: true })
        .toBuffer({ resolveWithObject: true });
      if (
        result.data.length <= PUBLIC_JOURNAL_STORED_BYTES &&
        result.info.width > 0 &&
        result.info.height > 0
      ) {
        return {
          data: result.data,
          width: result.info.width,
          height: result.info.height,
        };
      }
    }
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.warn("Public journal photo rejected during decode", error);
    throw new HttpsError("invalid-argument", "The photo could not be prepared.");
  }
  throw new HttpsError("invalid-argument", "The photo is too large to publish.");
}

/**
 * App Check済みのiOSアプリから改善案を受け取り、運営専用の非公開キューへ入れる。
 * Firebaseログインは任意とし、ローカルモードの利用者からも受け付ける。
 */
export const submitFeedback = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request) => {
    const category = requiredFeedbackString(request.data?.category, "category", 1, 20);
    if (!FEEDBACK_CATEGORIES.has(category)) {
      throw new HttpsError("invalid-argument", "Unknown feedback category.");
    }

    const message = requiredFeedbackString(request.data?.message, "message", 10, 1_200);
    const installationId = requiredFeedbackString(
      request.data?.installationId,
      "installationId",
      36,
      36,
    ).toLowerCase();
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(installationId)) {
      throw new HttpsError("invalid-argument", "installationId must be a UUID.");
    }

    const appVersion = requiredFeedbackString(request.data?.appVersion, "appVersion", 1, 40);
    const buildNumber = requiredFeedbackString(request.data?.buildNumber, "buildNumber", 1, 40);
    const osVersion = requiredFeedbackString(request.data?.osVersion, "osVersion", 1, 80);
    const locale = requiredFeedbackString(request.data?.locale, "locale", 1, 40);

    // UIDがあればアカウント、なければインストール単位で連投を抑える。
    // App Checkも強制するため、任意の外部クライアントからは到達できない。
    const actor = request.auth?.uid ? `uid:${request.auth.uid}` : `install:${installationId}`;
    const rateLimitId = createHash("sha256").update(actor).digest("hex");
    const rateLimitRef = db.collection("feedbackRateLimits").doc(rateLimitId);
    const feedbackRef = db.collection("feedback").doc();
    const now = Timestamp.now();

    await db.runTransaction(async (transaction) => {
      const rateLimit = await transaction.get(rateLimitRef);
      const lastSubmittedAt = rateLimit.get("lastSubmittedAt");
      const windowStartedAt = rateLimit.get("windowStartedAt");
      const storedCount = rateLimit.get("count");

      if (
        lastSubmittedAt instanceof Timestamp &&
        now.toMillis() - lastSubmittedAt.toMillis() < 15_000
      ) {
        throw new HttpsError("resource-exhausted", "Please wait before sending another note.");
      }

      const sameWindow =
        windowStartedAt instanceof Timestamp &&
        now.toMillis() - windowStartedAt.toMillis() < 60 * 60 * 1_000;
      const nextCount = sameWindow && typeof storedCount === "number" ? storedCount + 1 : 1;
      if (nextCount > 5) {
        throw new HttpsError("resource-exhausted", "The hourly feedback limit has been reached.");
      }

      transaction.set(rateLimitRef, {
        count: nextCount,
        lastSubmittedAt: now,
        windowStartedAt: sameWindow ? windowStartedAt : now,
      });
      transaction.create(feedbackRef, {
        category,
        message,
        status: "new",
        source: "ios",
        appId: request.app?.appId ?? null,
        appVersion,
        buildNumber,
        osVersion,
        locale,
        createdAt: now,
      });
    });

    return { feedbackId: feedbackRef.id };
  },
);

/**
 * 公開誌の「本日の一頁」を公開または更新する。
 * 日付・著者表示・1日1文書の制約はクライアント値を信用せず、ここで確定する。
 */
export const publishPublicJournalEntry = onCall(
  {
    region: REGION,
    enforceAppCheck: true,
    memory: "1GiB",
    timeoutSeconds: 60,
    maxInstances: 20,
  },
  async (request) => {
    const uid = requireUid(request.auth);
    const requestId = requiredFeedbackString(
      request.data?.requestId,
      "requestId",
      36,
      36,
    ).toLowerCase();
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u.test(requestId)) {
      throw new HttpsError("invalid-argument", "requestId must be a UUID.");
    }

    const harborSlug = requiredFeedbackString(
      request.data?.harborSlug,
      "harborSlug",
      1,
      24,
    );
    if (!PUBLIC_HARBORS.includes(harborSlug)) {
      throw new HttpsError("invalid-argument", "Unknown public harbor.");
    }
    const body = publicJournalText(request.data?.body);
    const replaceExisting = request.data?.replaceExisting === true;
    const intendedDayID = requiredFeedbackString(
      request.data?.intendedDayID,
      "intendedDayID",
      10,
      10,
    );
    const dayID = publicJournalDayId();
    if (
      !/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/u.test(intendedDayID) ||
      intendedDayID !== dayID
    ) {
      throw new HttpsError(
        "failed-precondition",
        "The publishing day changed. Refresh the page and try again.",
        { reason: "day-changed" },
      );
    }
    const memberRef = db.doc(`publicHarbors/${harborSlug}/members/${uid}`);
    if (!(await memberRef.get()).exists) {
      throw new HttpsError(
        "failed-precondition",
        "Join this public harbor before publishing.",
        { reason: "not-in-public-harbor" },
      );
    }

    await enforcePublicJournalPublishRateLimit(uid, requestId);
    const photo = await preparePublicJournalPhoto(request.data?.imageBase64);
    const entryRef = db.collection("publicJournalEntries").doc(`${uid}_${dayID}`);
    const now = Timestamp.now();
    let response = { entryId: entryRef.id, dayID, revision: 1, created: true };

    await db.runTransaction(async (transaction) => {
      const [member, existing] = await Promise.all([
        transaction.get(memberRef),
        transaction.get(entryRef),
      ]);
      if (!member.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Join this public harbor before publishing.",
          { reason: "not-in-public-harbor" },
        );
      }

      if (existing.exists && existing.get("requestId") === requestId) {
        response = {
          entryId: entryRef.id,
          dayID,
          revision: Number(existing.get("revision")) || 1,
          created: false,
        };
        return;
      }
      if (existing.exists && !replaceExisting) {
        throw new HttpsError(
          "already-exists",
          "A public journal page has already been published today.",
        );
      }
      if (existing.exists && existing.get("authorUid") !== uid) {
        throw new HttpsError("internal", "The public journal entry is inconsistent.");
      }

      const revision = existing.exists ? (Number(existing.get("revision")) || 1) + 1 : 1;
      const displayName = publicJournalMemberString(
        member.get("displayName"),
        "Sailor",
        60,
      );
      const styleToken = publicJournalToken(
        member.get("styleToken"),
        PUBLIC_JOURNAL_STYLE_TOKENS,
        "midnight",
      );
      const symbolToken = publicJournalSymbolToken(member.get("symbolToken"));
      transaction.set(entryRef, {
        authorUid: uid,
        dayID,
        harborSlug,
        displayName,
        styleToken,
        symbolToken,
        body,
        imageData: photo.data,
        imageWidth: photo.width,
        imageHeight: photo.height,
        requestId,
        revision,
        createdAt: existing.get("createdAt") instanceof Timestamp
          ? existing.get("createdAt")
          : now,
        updatedAt: now,
      });
      response = { entryId: entryRef.id, dayID, revision, created: !existing.exists };
    });

    return response;
  },
);

/** 本人の公開誌ページを削除する。 */
export const deletePublicJournalEntry = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request) => {
    const uid = requireUid(request.auth);
    const entryId = requiredFeedbackString(request.data?.entryId, "entryId", 1, 256);
    const entryRef = db.collection("publicJournalEntries").doc(entryId);
    await db.runTransaction(async (transaction) => {
      const entry = await transaction.get(entryRef);
      if (!entry.exists) return;
      if (entry.get("authorUid") !== uid) {
        throw new HttpsError("permission-denied", "Only the author can delete this page.");
      }
      transaction.delete(entryRef);
    });
    return { deleted: true };
  },
);

/** 公開誌または公開港プロフィールを、重複・連投を抑えて運営へ通報する。 */
export const submitPublicContentReport = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request) => {
    const reporterUid = requireUid(request.auth);
    const targetUid = requiredFeedbackString(request.data?.targetUid, "targetUid", 1, 128);
    if (targetUid === reporterUid) {
      throw new HttpsError("invalid-argument", "You cannot report yourself.");
    }
    const harborSlug = requiredFeedbackString(
      request.data?.harborSlug,
      "harborSlug",
      1,
      24,
    );
    if (!PUBLIC_HARBORS.includes(harborSlug)) {
      throw new HttpsError("invalid-argument", "Unknown public harbor.");
    }
    const reason = requiredFeedbackString(request.data?.reason, "reason", 1, 24);
    if (!PUBLIC_CONTENT_REPORT_REASONS.has(reason)) {
      throw new HttpsError("invalid-argument", "Unknown report reason.");
    }

    const rawEntryId = request.data?.entryId;
    const entryId = rawEntryId == null
      ? null
      : requiredFeedbackString(rawEntryId, "entryId", 1, 256);
    let bodySnapshot: string | null = null;
    let imageHash: string | null = null;
    let imageDataSnapshot: Buffer | null = null;
    let imageWidthSnapshot: number | null = null;
    let imageHeightSnapshot: number | null = null;
    let displayNameSnapshot: string | null = null;
    let styleTokenSnapshot: string | null = null;
    let symbolTokenSnapshot: string | null = null;
    let entryRevision: number | null = null;
    let profileSnapshot: Record<string, string | null> | null = null;
    let contentVersion: string;
    if (entryId) {
      const entry = await db.collection("publicJournalEntries").doc(entryId).get();
      if (
        !entry.exists ||
        entry.get("authorUid") !== targetUid ||
        entry.get("harborSlug") !== harborSlug
      ) {
        throw new HttpsError("not-found", "This public journal page is no longer available.");
      }
      bodySnapshot = typeof entry.get("body") === "string"
        ? String(entry.get("body"))
        : null;
      const storedImage = entry.get("imageData");
      if (Buffer.isBuffer(storedImage) || storedImage instanceof Uint8Array) {
        imageDataSnapshot = Buffer.from(storedImage);
        imageHash = createHash("sha256").update(imageDataSnapshot).digest("hex");
      }
      const storedWidth = Number(entry.get("imageWidth"));
      const storedHeight = Number(entry.get("imageHeight"));
      imageWidthSnapshot = Number.isSafeInteger(storedWidth) && storedWidth > 0
        ? storedWidth
        : null;
      imageHeightSnapshot = Number.isSafeInteger(storedHeight) && storedHeight > 0
        ? storedHeight
        : null;
      displayNameSnapshot = reportSnapshotString(entry.get("displayName"), 60);
      styleTokenSnapshot = reportSnapshotString(entry.get("styleToken"), 24);
      symbolTokenSnapshot = reportSnapshotString(entry.get("symbolToken"), 24);
      const storedRevision = Number(entry.get("revision"));
      entryRevision = Number.isSafeInteger(storedRevision) && storedRevision > 0
        ? storedRevision
        : 1;
      contentVersion = `revision:${entryRevision}`;
    } else {
      const member = await db.doc(`publicHarbors/${harborSlug}/members/${targetUid}`).get();
      if (!member.exists) {
        throw new HttpsError("not-found", "This public profile is no longer available.");
      }
      profileSnapshot = {
        displayName: reportSnapshotString(member.get("displayName"), 60),
        styleToken: reportSnapshotString(member.get("styleToken"), 24),
        symbolToken: reportSnapshotString(member.get("symbolToken"), 24),
        resolve: reportSnapshotString(member.get("resolve"), 80),
        sinceDay: reportSnapshotString(member.get("sinceDay"), 10),
        boatSail: reportSnapshotString(member.get("boatSail"), 24),
        boatJib: reportSnapshotString(member.get("boatJib"), 24),
        boatHull: reportSnapshotString(member.get("boatHull"), 24),
        boatStripe: reportSnapshotString(member.get("boatStripe"), 24),
        boatFlag: reportSnapshotString(member.get("boatFlag"), 24),
      };
      const profileHash = createHash("sha256")
        .update(JSON.stringify(profileSnapshot), "utf8")
        .digest("hex");
      contentVersion = `snapshot:${profileHash}`;
    }

    const contentKey = entryId
      ? `entry:${entryId}:${contentVersion}`
      : `profile:${harborSlug}:${targetUid}:${contentVersion}`;
    const reportId = createHash("sha256")
      .update(`${reporterUid}|${contentKey}`, "utf8")
      .digest("hex");
    const dayID = publicJournalDayId();
    const limitId = createHash("sha256")
      .update(`${reporterUid}|${dayID}`, "utf8")
      .digest("hex");
    const reportRef = db.collection("publicContentReports").doc(reportId);
    const limitRef = db.collection("publicContentReportLimits").doc(limitId);
    const now = Timestamp.now();
    let duplicate = false;

    await db.runTransaction(async (transaction) => {
      const [existing, limit] = await Promise.all([
        transaction.get(reportRef),
        transaction.get(limitRef),
      ]);
      if (existing.exists) {
        duplicate = true;
        return;
      }
      const count = Number(limit.get("count")) || 0;
      if (count >= 20) {
        throw new HttpsError("resource-exhausted", "The daily report limit has been reached.");
      }
      transaction.set(limitRef, {
        reporterUid,
        dayID,
        count: count + 1,
        updatedAt: now,
      });
      transaction.create(reportRef, {
        reporterUid,
        targetUid,
        harborSlug,
        entryId,
        contentKind: entryId ? "publicJournalEntry" : "publicHarborProfile",
        reason,
        contentVersion,
        entryRevision,
        bodySnapshot,
        imageHash,
        imageDataSnapshot,
        imageWidthSnapshot,
        imageHeightSnapshot,
        displayNameSnapshot,
        styleTokenSnapshot,
        symbolTokenSnapshot,
        profileSnapshot,
        status: "new",
        appId: request.app?.appId ?? null,
        createdAt: now,
      });
    });

    return { reported: true, duplicate };
  },
);

/**
 * プライベート島の発言は、改造クライアントからFirestoreへ直接連投させない。
 * App Check、所属確認、サーバー側の名前、本文検証、アカウント単位の速度制限を
 * 一つの取引で確定してから、全参加者が読む正規チャットへ追加する。
 */
export const sendPrivateIslandMessage = onCall(
  { region: REGION, enforceAppCheck: true, maxInstances: 40 },
  async (request) => {
    const uid = requireUid(request.auth);
    const code = privateIslandCode(request.data?.code);
    const messageId = privateIslandMessageId(request.data?.requestId);
    const text = privateIslandChatText(request.data?.text);
    const islandRef = db.doc(`privateIslands/${code}`);
    const memberRef = islandRef.collection("members").doc(uid);
    const messageRef = islandRef.collection("chat").doc(messageId);
    const rateLimitRef = db.collection("privateIslandChatRateLimits")
      .doc(hashedActorId("private-island-chat", uid));
    let duplicate = false;

    await db.runTransaction(async (transaction) => {
      const [island, member, existing, rateLimit] = await Promise.all([
        transaction.get(islandRef),
        transaction.get(memberRef),
        transaction.get(messageRef),
        transaction.get(rateLimitRef),
      ]);
      const memberIds = island.get("memberIds");
      if (
        !island.exists ||
        !Array.isArray(memberIds) ||
        !memberIds.includes(uid) ||
        !member.exists
      ) {
        throw new HttpsError("permission-denied", "Join this island before sending a message.");
      }
      if (existing.exists) {
        if (existing.get("uid") !== uid) {
          throw new HttpsError("already-exists", "That message identifier is already in use.");
        }
        duplicate = true;
        return;
      }

      const now = Timestamp.now();
      const windowStartedAt = rateLimit.get("windowStartedAt");
      const lastSentAt = rateLimit.get("lastSentAt");
      const storedCount = rateLimit.get("count");
      const sameWindow =
        windowStartedAt instanceof Timestamp &&
        now.toMillis() - windowStartedAt.toMillis() < 60 * 60 * 1_000;
      const count = sameWindow && typeof storedCount === "number" ? storedCount : 0;
      if (
        lastSentAt instanceof Timestamp &&
        now.toMillis() - lastSentAt.toMillis() < PRIVATE_ISLAND_CHAT_COOLDOWN_MS
      ) {
        throw new HttpsError("resource-exhausted", "Please wait before sending another message.");
      }
      if (count >= PRIVATE_ISLAND_CHAT_HOURLY_LIMIT) {
        throw new HttpsError("resource-exhausted", "The hourly message limit has been reached.");
      }

      const senderName = publicJournalMemberString(
        member.get("displayName"),
        "Sailor",
        60,
      );
      transaction.set(rateLimitRef, {
        uid,
        count: count + 1,
        windowStartedAt: sameWindow ? windowStartedAt : now,
        lastSentAt: now,
        updatedAt: now,
      });
      transaction.create(messageRef, {
        uid,
        senderName,
        kind: "text",
        text,
        createdAt: now,
      });
    });

    return { messageId, duplicate };
  },
);

/** プライベート島の実在する他人の発言だけを、重複・連投を抑えて通報する。 */
export const submitPrivateIslandChatReport = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request) => {
    const reporterUid = requireUid(request.auth);
    const code = privateIslandCode(request.data?.code);
    const messageId = privateIslandMessageId(request.data?.messageId);
    const targetUid = requiredFeedbackString(request.data?.targetUid, "targetUid", 1, 128);
    if (targetUid === reporterUid) {
      throw new HttpsError("invalid-argument", "You cannot report yourself.");
    }

    const dayId = publicJournalDayId();
    const reportId = hashedActorId(
      "private-island-report",
      `${reporterUid}|${code}|${messageId}`,
    );
    const limitId = hashedActorId("private-island-report-limit", `${reporterUid}|${dayId}`);
    const islandRef = db.doc(`privateIslands/${code}`);
    const messageRef = islandRef.collection("chat").doc(messageId);
    const reportRef = db.collection("reports").doc(reportId);
    const limitRef = db.collection("privateIslandReportLimits").doc(limitId);
    let duplicate = false;

    await db.runTransaction(async (transaction) => {
      const [island, message, existing, limit] = await Promise.all([
        transaction.get(islandRef),
        transaction.get(messageRef),
        transaction.get(reportRef),
        transaction.get(limitRef),
      ]);
      const memberIds = island.get("memberIds");
      if (
        !island.exists ||
        !Array.isArray(memberIds) ||
        !memberIds.includes(reporterUid)
      ) {
        throw new HttpsError("permission-denied", "Only island members can report this message.");
      }
      if (!message.exists || message.get("uid") !== targetUid) {
        throw new HttpsError("not-found", "This message is no longer available.");
      }
      if (existing.exists) {
        duplicate = true;
        return;
      }

      const storedCount = limit.get("count");
      const count = typeof storedCount === "number" && Number.isSafeInteger(storedCount)
        ? storedCount
        : 0;
      if (count >= PRIVATE_ISLAND_REPORT_DAILY_LIMIT) {
        throw new HttpsError("resource-exhausted", "The daily report limit has been reached.");
      }
      const now = Timestamp.now();
      transaction.set(limitRef, {
        reporterUid,
        dayId,
        count: count + 1,
        updatedAt: now,
      });
      transaction.create(reportRef, {
        source: "privateIsland",
        privateIslandCode: code,
        reporterUid,
        targetUid,
        messageId,
        text: reportSnapshotString(message.get("text"), PRIVATE_ISLAND_CHAT_LIMIT) ?? "",
        status: "new",
        appId: request.app?.appId ?? null,
        createdAt: now,
      });
    });

    return { reported: true, duplicate };
  },
);

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
  { region: REGION, enforceAppCheck: true },
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
    enforceAppCheck: true,
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
    enforceAppCheck: true,
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

async function deleteQueryDocumentsInPages(
  query: FirebaseFirestore.Query,
  pageSize = 200,
): Promise<void> {
  while (true) {
    // select() with no fields retrieves document names only, avoiding large image payloads.
    const page = await query.select().limit(pageSize).get();
    if (page.empty) return;
    await deleteDocuments(page.docs);
  }
}

async function deleteSharedUserContent(uid: string): Promise<void> {
  // v2のプライベート島。ホストのアカウントが消えた場合は、
  // 他人の島へ譲渡せず島全体を消す。参加者なら本人のカードと
  // presenceを消し、メンバー一覧から本人だけを外す。
  const privateIslands = await db.collection("privateIslands")
    .where("memberIds", "array-contains", uid)
    .get();
  for (const island of privateIslands.docs) {
    if (island.get("hostUid") === uid) {
      await db.recursiveDelete(island.ref);
    } else {
      await Promise.all([
        db.recursiveDelete(island.ref.collection("members").doc(uid)),
        island.ref.collection("presence").doc(uid).delete().catch(() => undefined),
      ]);
      await island.ref.update({ memberIds: FieldValue.arrayRemove(uid) });
    }
  }

  // 退島済みの過去ルームに残る発言も、アカウント削除時には消す。
  // collectionGroupは旧roomsと新privateIslandsの両方を拾う。
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

  // 公開誌はトップレベルに置くため、ユーザーツリーとは別に本人の全頁を削除する。
  // 画像本体を含む全文書をメモリに読まず、文書名だけを有界ページで消す。
  await deleteQueryDocumentsInPages(
    db.collection("publicJournalEntries").where("authorUid", "==", uid),
  );

  // 安全対応の通報証跡は保持するが、失効済みの連投制限は個人データとして残さない。
  await deleteQueryDocumentsInPages(
    db.collection("publicContentReportLimits").where("reporterUid", "==", uid),
  );
  await Promise.all([
    db.collection("publicJournalPublishRateLimits")
      .doc(publicJournalRateLimitId(uid))
      .delete(),
    db.collection("feedbackRateLimits")
      .doc(createHash("sha256").update(`uid:${uid}`).digest("hex"))
      .delete(),
  ]);

  // users/{uid} 自体が無くても、全サブコレクションを再帰削除する。
  await db.recursiveDelete(db.doc(`users/${uid}`));
}

// One-time v1 -> v2 cutover. The old Private Harbor stored study records,
// shared timers, quests and chat below `rooms/{code}`. The replacement uses a
// separate `privateIslands` root and intentionally does not migrate that data.
// Keeping this as a developer-only callable gives the operation an auditable,
// exact target and lets recursiveDelete remove every nested subcollection.
export const purgeLegacyPrivateRooms = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 540, memory: "512MiB" },
  async (request) => {
    if (!isDeveloper(request.auth)) {
      throw new HttpsError("permission-denied", "Developer access is required.");
    }

    let deletedRooms = 0;
    while (true) {
      const page = await db.collection("rooms").limit(50).get();
      if (page.empty) break;
      for (const room of page.docs) {
        await db.recursiveDelete(room.ref);
        deletedRooms += 1;
      }
    }
    return { deletedRooms };
  },
);

/**
 * Publishes the signed-in sailor's current public-harbor month through a
 * bounded, App Check protected path. Direct month writes are denied by rules,
 * so a modified client cannot manufacture unbounded document IDs or nested
 * payloads at the project's expense.
 */
export const publishPublicHarborMonth = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 60, memory: "256MiB" },
  async (request) => {
    const uid = requireUid(request.auth);
    const monthId = typeof request.data?.monthId === "string" ? request.data.monthId : "";
    if (!validMonthIds().has(monthId)) {
      throw new HttpsError("invalid-argument", "Only the current local month can be published.");
    }

    const rawSlugs = request.data?.slugs;
    if (!Array.isArray(rawSlugs) || rawSlugs.length < 1 || rawSlugs.length > PUBLIC_HARBORS.length) {
      throw new HttpsError("invalid-argument", "At least one official harbor is required.");
    }
    const slugs = rawSlugs.map((slug) => {
      if (typeof slug !== "string" || !PUBLIC_HARBORS.includes(slug)) {
        throw new HttpsError("invalid-argument", "An unknown public harbor was supplied.");
      }
      return slug;
    });
    if (new Set(slugs).size !== slugs.length) {
      throw new HttpsError("invalid-argument", "A public harbor cannot be duplicated.");
    }
    const [monthYear, monthNumber] = monthId.split("-").map(Number);
    const maximumDay = new Date(Date.UTC(monthYear, monthNumber, 0)).getUTCDate();
    const payload = publicHarborMonthPayload(request.data?.payload, maximumDay);
    const now = Timestamp.now();
    const rateLimitRef = db.collection("publicHarborMonthPublishLimits")
      .doc(hashedActorId("public-harbor-month", uid));
    const memberRefs = slugs.map((slug) =>
      db.doc(`publicHarbors/${slug}/members/${uid}`));

    await db.runTransaction(async (transaction) => {
      const [rateLimit, ...members] = await Promise.all([
        transaction.get(rateLimitRef),
        ...memberRefs.map((ref) => transaction.get(ref)),
      ]);
      if (members.some((member) => !member.exists)) {
        throw new HttpsError(
          "failed-precondition",
          "Join every selected public harbor before publishing.",
        );
      }

      const windowStartedAt = rateLimit.get("windowStartedAt");
      const storedCount = rateLimit.get("count");
      const sameWindow = windowStartedAt instanceof Timestamp &&
        now.toMillis() - windowStartedAt.toMillis() < 60 * 60 * 1_000;
      const nextCount = sameWindow && typeof storedCount === "number" ? storedCount + 1 : 1;
      if (nextCount > PUBLIC_HARBOR_MONTH_HOURLY_LIMIT) {
        throw new HttpsError("resource-exhausted", "The hourly month publishing limit was reached.");
      }

      transaction.set(rateLimitRef, {
        count: nextCount,
        windowStartedAt: sameWindow ? windowStartedAt : now,
        updatedAt: now,
      });
      for (let index = 0; index < slugs.length; index += 1) {
        transaction.set(memberRefs[index].collection("months").doc(monthId), {
          days: payload.days,
          sessions: payload.sessions,
          updatedAt: now,
        });
      }
    });
    return { published: true, monthId, harborCount: slugs.length };
  },
);

// Joining by invite code happens here, never in the client, so the island
// document itself can stay unreadable to non-members. A client-side join needs
// read access to any island by id, which turns the six-character code into a
// space small enough to sweep for island names and member uids.
//
// The callable must not become the same oracle in disguise: a wrong code costs
// an attempt, and attempts are capped per account per hour.
// PrivateIslandRoom.maxMembers / .maxJoined と同じ値。片方だけ動かさないこと。
const PRIVATE_ISLAND_MAX_MEMBERS = 8;
const PRIVATE_ISLAND_MAX_JOINED = 3;
const PRIVATE_ISLAND_JOIN_ATTEMPTS_PER_HOUR = 20;
const PRIVATE_ISLAND_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function generatedPrivateIslandCode(): string {
  return Array.from(randomBytes(6), (byte) =>
    PRIVATE_ISLAND_CODE_ALPHABET[byte & 31]).join("");
}

async function hasActiveVoyagePass(
  transaction: FirebaseFirestore.Transaction,
  uid: string,
): Promise<boolean> {
  const [stripePass, appStorePass] = await Promise.all([
    transaction.get(db.doc(`users/${uid}/entitlements/${VOYAGE_PASS_ENTITLEMENT}`)),
    transaction.get(db.doc(`users/${uid}/entitlements/${APP_STORE_VOYAGE_PASS_ENTITLEMENT}`)),
  ]);
  const now = Timestamp.now().toMillis();
  return [stripePass, appStorePass].some((snapshot) => {
    const end = snapshot.get("currentPeriodEnd");
    return snapshot.get("active") === true && end instanceof Timestamp && end.toMillis() > now;
  });
}

type PrivateIslandJoinOutcome =
  | {
    status: "joined" | "already-member";
    name: string;
    hostUid: string;
    memberIds: string[];
    createdAt: number | null;
  }
  | {
    status: "rate-limited" | "not-found" | "island-full" | "membership-limit";
  };

type PrivateIslandCreateOutcome =
  | { status: "created" | "already-hosts"; code: string }
  | { status: "collision" | "membership-limit" | "pass-required" };

/**
 * Creates at most one hosted island per account. A per-user transaction lock
 * serializes concurrent requests, while the server generates both the invite
 * code and independent 256-bit EOS credentials. Firestore rules deny the
 * equivalent direct client create.
 */
export const createPrivateIsland = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request) => {
    const uid = requireUid(request.auth);
    const name = boundedPublicString(request.data?.name, 80)?.trim() ?? "";
    if (!name) throw new HttpsError("invalid-argument", "Give the island a name.");
    const member = request.data?.member;
    const joinedQuery = db.collection("privateIslands")
      .where("memberIds", "array-contains", uid)
      .limit(PRIVATE_ISLAND_MAX_JOINED + 1);
    const creationLockRef = db.collection("privateIslandCreationLocks").doc(uid);

    for (let attempt = 0; attempt < 12; attempt += 1) {
      const code = generatedPrivateIslandCode();
      const islandRef = db.collection("privateIslands").doc(code);
      const outcome = await db.runTransaction<PrivateIslandCreateOutcome>(async (transaction) => {
        const creationLock = await transaction.get(creationLockRef);
        const [joined, island] = await Promise.all([
          transaction.get(joinedQuery),
          transaction.get(islandRef),
        ]);
        const hosted = joined.docs.find((document) => document.get("hostUid") === uid);
        if (hosted) return { status: "already-hosts", code: hosted.id };
        if (joined.size >= PRIVATE_ISLAND_MAX_JOINED) return { status: "membership-limit" };
        if (!isDeveloper(request.auth) && !(await hasActiveVoyagePass(transaction, uid))) {
          return { status: "pass-required" };
        }
        if (island.exists) return { status: "collision" };

        const now = Timestamp.now();
        transaction.set(creationLockRef, {
          revision: (typeof creationLock.get("revision") === "number"
            ? creationLock.get("revision") as number
            : 0) + 1,
          updatedAt: now,
        });
        transaction.create(islandRef, {
          schemaVersion: 2,
          name,
          hostUid: uid,
          memberIds: [uid],
          createdAt: now,
        });
        transaction.create(islandRef.collection("members").doc(uid),
          privateIslandMemberData(member, now));
        transaction.create(islandRef.collection("runtime").doc("eos"), {
          schemaVersion: 1,
          sessionLocator: randomBytes(32).toString("base64url"),
          socketSecret: randomBytes(32).toString("base64url"),
          createdAt: now,
        });
        return { status: "created", code };
      });

      switch (outcome.status) {
        case "created":
        case "already-hosts":
          return { code: outcome.code, alreadyExisted: outcome.status === "already-hosts" };
        case "membership-limit":
          throw new HttpsError("failed-precondition", "The private-island membership limit was reached.");
        case "pass-required":
          throw new HttpsError("permission-denied", "An active Voyage Pass is required.");
        case "collision":
          break;
      }
    }
    throw new HttpsError("unavailable", "An invite code could not be allocated. Please try again.");
  },
);

export const joinPrivateIsland = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request) => {
    const uid = requireUid(request.auth);
    const code = typeof request.data?.code === "string"
      ? request.data.code.trim().toUpperCase()
      : "";
    if (!PRIVATE_ISLAND_CODE.test(code)) {
      throw new HttpsError("invalid-argument", "That invite code is not valid.");
    }

    const joinedQuery = db
      .collection("privateIslands")
      .where("memberIds", "array-contains", uid);
    const islandRef = db.collection("privateIslands").doc(code);
    const rateLimitRef = db.collection("privateIslandJoinLimits").doc(uid);

    // The rate-limit document is intentionally read and written in the same
    // transaction as membership. Every concurrent join for one account now
    // contends on that shared document, so two requests cannot both observe
    // the old membership count and slip past maxJoined.
    const outcome = await db.runTransaction<PrivateIslandJoinOutcome>(async (transaction) => {
      const [rateLimit, joined, island] = await Promise.all([
        transaction.get(rateLimitRef),
        transaction.get(joinedQuery),
        transaction.get(islandRef),
      ]);
      const now = Timestamp.now();
      const windowStart = Timestamp.fromMillis(now.toMillis() - 60 * 60 * 1_000);
      const since = rateLimit.get("windowStartedAt");
      const withinWindow =
        since instanceof Timestamp && since.toMillis() > windowStart.toMillis();
      const storedAttempts = rateLimit.get("attempts");
      const attempts =
        withinWindow && typeof storedAttempts === "number" && Number.isSafeInteger(storedAttempts)
          ? storedAttempts
          : 0;
      if (attempts >= PRIVATE_ISLAND_JOIN_ATTEMPTS_PER_HOUR) {
        return { status: "rate-limited" };
      }

      // Invalid and full codes still consume an attempt. Returning an outcome
      // instead of throwing lets the rate-limit write commit before the public
      // error is raised outside the transaction.
      transaction.set(rateLimitRef, {
        attempts: attempts + 1,
        windowStartedAt: withinWindow ? since : now,
        updatedAt: now,
      });

      if (!island.exists) {
        return { status: "not-found" };
      }
      const current = (island.get("memberIds") as string[] | undefined) ?? [];
      if (current.includes(uid)) {
        return {
          status: "already-member",
          name: island.get("name") ?? "",
          hostUid: island.get("hostUid") ?? "",
          memberIds: current,
          createdAt: (island.get("createdAt") as Timestamp | undefined)?.toMillis() ?? null,
        };
      }
      if (current.length >= PRIVATE_ISLAND_MAX_MEMBERS) {
        return { status: "island-full" };
      }
      if (joined.size >= PRIVATE_ISLAND_MAX_JOINED) {
        return { status: "membership-limit" };
      }

      const next = [...current, uid];
      transaction.update(islandRef, { memberIds: next });
      return {
        status: "joined",
        name: island.get("name") ?? "",
        hostUid: island.get("hostUid") ?? "",
        memberIds: next,
        createdAt: (island.get("createdAt") as Timestamp | undefined)?.toMillis() ?? null,
      };
    });

    switch (outcome.status) {
      case "rate-limited":
        throw new HttpsError(
          "resource-exhausted",
          "Too many invite codes tried. Please wait a while before trying again.",
        );
      case "not-found":
        throw new HttpsError("not-found", "No island answers that invite code.");
      case "island-full":
        throw new HttpsError("resource-exhausted", "That island is full.");
      case "membership-limit":
        throw new HttpsError(
          "failed-precondition",
          "You have joined as many islands as one navigator can hold.",
        );
      case "joined":
      case "already-member":
        break;
    }

    return {
      id: code,
      name: outcome.name,
      hostUid: outcome.hostUid,
      memberIds: outcome.memberIds,
      // 再訪かどうか。端末はこれを見て joinedAt を書き換えないと判断する。
      alreadyMember: outcome.status === "already-member",
      createdAt: outcome.createdAt,
    };
  },
);

// The harbor board reads members ordered by joinedAt with a page limit, so the
// board stays cheap no matter how large a harbor grows. Cards written before
// joinedAt existed carry no value for that ordering and would silently drop out
// of the query, so stamp them once with their earliest known moment.
//
// Developer-only and idempotent: cards that already carry joinedAt are skipped,
// so it is safe to run again after a partial pass or a timeout.
export const backfillPublicHarborJoinedAt = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 540, memory: "512MiB" },
  async (request) => {
    if (!isDeveloper(request.auth)) {
      throw new HttpsError("permission-denied", "Developer access is required.");
    }

    let stamped = 0;
    let scanned = 0;
    for (const slug of PUBLIC_HARBORS) {
      const members = db.collection("publicHarbors").doc(slug).collection("members");
      let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;

      while (true) {
        let page = members.orderBy(FieldPath.documentId()).limit(200);
        if (cursor) page = page.startAfter(cursor);
        const snapshot = await page.get();
        if (snapshot.empty) break;

        const batch = db.batch();
        let pending = 0;
        for (const card of snapshot.docs) {
          scanned += 1;
          if (card.get("joinedAt") !== undefined) continue;
          // 参加日時が分からないカードは、板の最後尾に並ぶ最古の時刻を与える。
          // 実際より古く見せる分には、誰かの順位を不当に押し上げることがない。
          batch.update(card.ref, { joinedAt: Timestamp.fromMillis(0) });
          pending += 1;
        }
        if (pending > 0) {
          await batch.commit();
          stamped += pending;
        }

        cursor = snapshot.docs[snapshot.docs.length - 1];
        if (snapshot.size < 200) break;
      }
    }
    return { scanned, stamped };
  },
);

// Hosts can retire a v2 private island without leaving orphaned nested chat,
// presence, member cards or snapshots. Membership is re-checked server-side;
// knowing the six-character invite code is never sufficient for deletion.
export const closePrivateIsland = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 120, memory: "256MiB" },
  async (request) => {
    const uid = requireUid(request.auth);
    const rawCode = typeof request.data?.code === "string" ? request.data.code : "";
    const code = rawCode.trim().toUpperCase();
    if (!/^[A-Z0-9]{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "A valid invite code is required.");
    }

    const island = db.doc(`privateIslands/${code}`);
    const snapshot = await island.get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "The private island was not found.");
    }
    if (snapshot.get("hostUid") !== uid) {
      throw new HttpsError("permission-denied", "Only the island host can close it.");
    }
    await db.recursiveDelete(island);
    return { closed: true, code };
  },
);

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
