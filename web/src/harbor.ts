import {
  addDoc,
  arrayRemove,
  arrayUnion,
  collection,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  limit,
  limitToLast,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} from "firebase/firestore";
import { auth, db } from "./firebase";
import { PlayerProfile } from "./profile";
import { startOfDay, type StudyDay, type StudyItem, type StudySession } from "./types";
import type { I18nKey } from "./i18n";

// 港(プライベート rooms / パブリック publicHarbors)とチャット。
// Firestore の形式は iOS の RoomService / PublicHarborService / HarborChatService と同一
// (契約は docs/SCHEMA.md)。

// ---- カタログ(パブリック5港。slug は firestore.rules の許可リストと一致) ----

export interface PublicHarborInfo {
  slug: string;
  titleKey: I18nKey;
  taglineKey: I18nKey;
  styleToken: string;
  symbolToken: string;
}

export const PUBLIC_HARBORS: PublicHarborInfo[] = [
  { slug: "language", titleKey: "harborLanguage", taglineKey: "tagLanguage", styleToken: "seaGreen", symbolToken: "compass" },
  { slug: "certification", titleKey: "harborCertification", taglineKey: "tagCertification", styleToken: "midnight", symbolToken: "lighthouse" },
  { slug: "student", titleKey: "harborStudent", taglineKey: "tagStudent", styleToken: "coral", symbolToken: "phoenix" },
  { slug: "reading", titleKey: "harborReading", taglineKey: "tagReading", styleToken: "violet", symbolToken: "book" },
  { slug: "making", titleKey: "harborMaking", taglineKey: "tagMaking", styleToken: "sunYellow", symbolToken: "pen" },
];

// ---- 型 ----

export interface HarborRoom {
  id: string; // 6文字の招待コードがそのままID
  name: string;
  memberIds: string[];
  ownerUid?: string;
}

export const ROOM_MAX_MEMBERS = 4;
export const ROOM_MAX_JOINED = 3;

export interface HarborMember {
  id: string; // uid
  displayName: string;
  styleToken: string;
  symbolToken: string;
  resolve: string;
}

export interface SharedSession {
  day: number;
  minutes: number;
  note?: string;
  itemName?: string;
  styleToken: string;
  symbolToken: string;
}

export interface SharedMonth {
  days: number[];
  sessions: SharedSession[];
}

export type ChatKind = "text" | "landfall" | "return";

export interface ChatMessage {
  id: string;
  uid: string;
  kind: ChatKind;
  text?: string;
  itemName?: string;
  itemStyle?: string;
  itemSymbol?: string;
  minutes?: number;
  gapDays?: number;
  createdAt: Date;
  reactions: Record<string, string>; // uid → lighthouse | anchor | phoenix
}

export const CHAT_REACTIONS = ["lighthouse", "anchor", "phoenix"] as const;

export type HarborErrorCode =
  | "notSignedIn"
  | "roomFull"
  | "tooManyRooms"
  | "alreadyOwnsRoom"
  | "roomNotFound"
  | "codeUnavailable";

export class HarborError extends Error {
  code: HarborErrorCode;

  constructor(code: HarborErrorCode) {
    super(code);
    this.code = code;
  }
}

function uid(): string {
  const u = auth.currentUser?.uid;
  if (!u) throw new HarborError("notSignedIn");
  return u;
}

// ---- プライベートの港(rooms) ----

export async function fetchRooms(): Promise<HarborRoom[]> {
  const u = uid();
  const snap = await getDocs(
    query(collection(db, "rooms"), where("memberIds", "array-contains", u)),
  );
  return snap.docs.map((d) => {
    const v = d.data();
    return {
      id: d.id,
      name: String(v.name ?? ""),
      memberIds: (v.memberIds as string[]) ?? [],
      ownerUid: typeof v.ownerUid === "string" ? v.ownerUid : undefined,
    };
  });
}

/// iOS と同じ紛らわしくない文字集合(I/O/0/1 なし)。
function generateCode(): string {
  const charset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let s = "";
  for (let i = 0; i < 6; i++) s += charset[Math.floor(Math.random() * charset.length)];
  return s;
}

async function reserveUnusedCode(): Promise<string> {
  for (let i = 0; i < 6; i++) {
    const code = generateCode();
    const snap = await getDoc(doc(db, "rooms", code));
    if (!snap.exists()) return code;
  }
  throw new HarborError("codeUnavailable");
}

/// 港をひらく。ひとり1港・同時に入れるのは3港まで。
export async function createRoom(
  name: string,
  data: PublishSource,
): Promise<string> {
  const u = uid();
  const rooms = await fetchRooms();
  if (rooms.length >= ROOM_MAX_JOINED) throw new HarborError("tooManyRooms");
  const mine = await getDocs(
    query(collection(db, "rooms"), where("ownerUid", "==", u), where("memberIds", "array-contains", u), limit(1)),
  );
  if (!mine.empty) throw new HarborError("alreadyOwnsRoom");

  const code = await reserveUnusedCode();
  await setDoc(doc(db, "rooms", code), {
    name: name.slice(0, 80),
    memberIds: [u],
    ownerUid: u,
    createdAt: serverTimestamp(),
  });
  await joinedSetup("rooms", code, data);
  return code;
}

/// 招待コードで港に入る。
export async function joinRoom(rawCode: string, data: PublishSource): Promise<void> {
  const u = uid();
  const code = rawCode.trim().toUpperCase();
  if (!code) throw new HarborError("roomNotFound");
  const ref = doc(db, "rooms", code);
  const snap = await getDoc(ref).catch(() => null);
  if (!snap || !snap.exists()) throw new HarborError("roomNotFound");
  const members = (snap.data().memberIds as string[]) ?? [];
  if (!members.includes(u)) {
    const rooms = await fetchRooms();
    if (rooms.length >= ROOM_MAX_JOINED) throw new HarborError("tooManyRooms");
    if (members.length >= ROOM_MAX_MEMBERS) throw new HarborError("roomFull");
    await updateDoc(ref, { memberIds: arrayUnion(u) });
  }
  await joinedSetup("rooms", code, data);
}

/// 退港。自分の共有分(プロフィール+月間記録)を消してから抜ける。
export async function leaveRoom(roomId: string): Promise<void> {
  const u = uid();
  const memberRef = doc(db, "rooms", roomId, "members", u);
  const months = await getDocs(collection(memberRef, "months")).catch(() => null);
  for (const m of months?.docs ?? []) await deleteDoc(m.ref).catch(() => {});
  await deleteDoc(memberRef).catch(() => {});
  await updateDoc(doc(db, "rooms", roomId), { memberIds: arrayRemove(u) }).catch(() => {});
}

// ---- パブリックの港(publicHarbors) ----

const JOINED_CACHE_KEY = "publicHarbor.joined";

export async function fetchPublicJoined(): Promise<Set<string>> {
  const u = uid();
  const found = new Set<string>();
  for (const harbor of PUBLIC_HARBORS) {
    const snap = await getDoc(
      doc(db, "publicHarbors", harbor.slug, "members", u),
    ).catch(() => null);
    if (snap?.exists()) found.add(harbor.slug);
  }
  localStorage.setItem(JOINED_CACHE_KEY, JSON.stringify([...found].sort()));
  return found;
}

export function cachedPublicJoined(): Set<string> {
  try {
    return new Set(JSON.parse(localStorage.getItem(JOINED_CACHE_KEY) ?? "[]") as string[]);
  } catch {
    return new Set();
  }
}

export async function joinPublic(slug: string, data: PublishSource): Promise<void> {
  await joinedSetup("publicHarbors", slug, data);
  const joined = cachedPublicJoined();
  joined.add(slug);
  localStorage.setItem(JOINED_CACHE_KEY, JSON.stringify([...joined].sort()));
}

export async function leavePublic(slug: string): Promise<void> {
  const u = uid();
  const memberRef = doc(db, "publicHarbors", slug, "members", u);
  const months = await getDocs(collection(memberRef, "months")).catch(() => null);
  for (const m of months?.docs ?? []) await deleteDoc(m.ref).catch(() => {});
  await deleteDoc(memberRef).catch(() => {});
  const joined = cachedPublicJoined();
  joined.delete(slug);
  localStorage.setItem(JOINED_CACHE_KEY, JSON.stringify([...joined].sort()));
}

export async function leaveAllPublic(): Promise<void> {
  const joined = await fetchPublicJoined();
  for (const slug of joined) await leavePublic(slug);
}

// ---- 参加時の共通処理・プロフィール反映 ----

async function joinedSetup(
  root: "rooms" | "publicHarbors",
  id: string,
  data: PublishSource,
): Promise<void> {
  const u = uid();
  await setDoc(doc(db, root, id, "members", u), {
    ...PlayerProfile.harborProfileData(),
    joinedAt: serverTimestamp(),
  });
  const payload = buildMonthPayload(data);
  if (payload) {
    await setDoc(
      doc(db, root, id, "members", u, "months", payload.docID),
      payload.data,
    ).catch(() => {});
  }
}

/// プレイヤーカードの変更を、参加中の全ての港へ反映する。
export async function pushProfileEverywhere(): Promise<void> {
  const u = uid();
  const rooms = await fetchRooms().catch(() => [] as HarborRoom[]);
  for (const room of rooms) {
    await setDoc(doc(db, "rooms", room.id, "members", u), PlayerProfile.harborProfileData(), {
      merge: true,
    }).catch(() => {});
  }
  for (const slug of cachedPublicJoined()) {
    await setDoc(
      doc(db, "publicHarbors", slug, "members", u),
      PlayerProfile.harborProfileData(),
      { merge: true },
    ).catch(() => {});
  }
}

// ---- メンバーと月間記録の閲覧 ----

export async function fetchMembers(
  root: "rooms" | "publicHarbors",
  id: string,
): Promise<HarborMember[]> {
  const snap = await getDocs(
    query(collection(db, root, id, "members"), orderBy("joinedAt", "desc"), limit(200)),
  ).catch(() => null);
  if (!snap) return [];
  return snap.docs.map((d) => {
    const v = d.data();
    return {
      id: d.id,
      displayName: String(v.displayName ?? ""),
      styleToken: String(v.styleToken ?? "midnight"),
      symbolToken: String(v.symbolToken ?? "phoenix"),
      resolve: String(v.resolve ?? ""),
    };
  });
}

export async function fetchMonth(
  root: "rooms" | "publicHarbors",
  id: string,
  memberId: string,
  ym: string,
): Promise<SharedMonth | null> {
  const snap = await getDoc(
    doc(db, root, id, "members", memberId, "months", ym),
  ).catch(() => null);
  if (!snap || !snap.exists()) return null;
  const v = snap.data();
  const days = ((v.days as number[]) ?? []).filter((n) => typeof n === "number");
  const sessions = (((v.sessions as Record<string, unknown>[]) ?? []) as Record<string, unknown>[])
    .map((s) => ({
      day: Number(s.day ?? 0),
      minutes: Number(s.minutes ?? 0),
      note: typeof s.note === "string" ? s.note : undefined,
      itemName: typeof s.itemName === "string" ? s.itemName : undefined,
      styleToken: typeof s.styleToken === "string" ? s.styleToken : "midnight",
      symbolToken: typeof s.symbolToken === "string" ? s.symbolToken : "compass",
    }))
    .filter((s) => s.day >= 1);
  return { days, sessions };
}

// ---- 記録の公開(月間ペイロード) ----

export interface PublishSource {
  items: StudyItem[];
  sessions: StudySession[];
  days: StudyDay[];
}

/// 当月の共有ペイロード。iOS の RoomService.monthPayload と同じ形式。
export function buildMonthPayload(
  data: PublishSource,
): { docID: string; data: Record<string, unknown> } | null {
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth(); // 0-based
  const docID = `${year}-${String(month + 1).padStart(2, "0")}`;

  const days = data.days
    .filter((d) => d.date.getFullYear() === year && d.date.getMonth() === month)
    .map((d) => d.date.getDate())
    .sort((a, b) => a - b);

  const itemById = new Map(data.items.map((i) => [i.id, i]));
  const sessions = data.sessions
    .filter((s) => s.date.getFullYear() === year && s.date.getMonth() === month)
    .slice(0, 1000)
    .map((s) => {
      const item = s.itemUUID ? itemById.get(s.itemUUID) : undefined;
      return {
        day: s.date.getDate(),
        minutes: s.minutes,
        date: s.date,
        ...(s.note ? { note: s.note.slice(0, 120) } : {}),
        ...(item
          ? {
              itemName: item.name.slice(0, 60),
              styleToken: item.styleToken,
              symbolToken: item.symbolToken,
            }
          : {}),
      };
    });

  return { docID, data: { days, sessions, updatedAt: serverTimestamp() } };
}

/// 当月の記録を、参加中の全ての港(プライベート+パブリック)に書く。
/// 記録の保存・編集・削除のたびに呼ぶ(iOS の publishCurrentMonth と同じ)。
export async function publishCurrentMonth(data: PublishSource): Promise<void> {
  const u = auth.currentUser?.uid;
  if (!u) return;
  const payload = buildMonthPayload(data);
  if (!payload) return;
  const rooms = await fetchRooms().catch(() => [] as HarborRoom[]);
  for (const room of rooms) {
    await setDoc(
      doc(db, "rooms", room.id, "members", u, "months", payload.docID),
      payload.data,
    ).catch(() => {});
  }
  for (const slug of cachedPublicJoined()) {
    await setDoc(
      doc(db, "publicHarbors", slug, "members", u, "months", payload.docID),
      payload.data,
    ).catch(() => {});
  }
}

// ---- チャット(プライベートのみ) ----

function chatRef(roomId: string) {
  return collection(db, "rooms", roomId, "chat");
}

export function listenChat(
  roomId: string,
  cb: (messages: ChatMessage[]) => void,
): () => void {
  return onSnapshot(
    query(chatRef(roomId), orderBy("createdAt"), limitToLast(120)),
    (snap) => {
      cb(
        snap.docs.map((d) => {
          const v = d.data();
          return {
            id: d.id,
            uid: String(v.uid ?? ""),
            kind: (v.kind as ChatKind) ?? "text",
            text: typeof v.text === "string" ? v.text : undefined,
            itemName: typeof v.itemName === "string" ? v.itemName : undefined,
            itemStyle: typeof v.itemStyle === "string" ? v.itemStyle : undefined,
            itemSymbol: typeof v.itemSymbol === "string" ? v.itemSymbol : undefined,
            minutes: typeof v.minutes === "number" ? v.minutes : undefined,
            gapDays: typeof v.gapDays === "number" ? v.gapDays : undefined,
            createdAt: v.createdAt instanceof Timestamp ? v.createdAt.toDate() : new Date(),
            reactions: (v.reactions as Record<string, string>) ?? {},
          };
        }),
      );
    },
    () => cb([]),
  );
}

export async function sendChat(roomId: string, text: string): Promise<void> {
  const u = uid();
  const trimmed = text.trim().slice(0, 500);
  if (!trimmed) return;
  await addDoc(chatRef(roomId), {
    uid: u,
    kind: "text",
    text: trimmed,
    createdAt: serverTimestamp(),
    reactions: {},
  });
}

export async function deleteChat(roomId: string, messageId: string): Promise<void> {
  await deleteDoc(doc(chatRef(roomId), messageId));
}

/// リアクション。同じ印をもう一度押すと消える(1人1つ)。
export async function reactChat(
  roomId: string,
  message: ChatMessage,
  token: string,
): Promise<void> {
  const u = uid();
  const current = message.reactions[u];
  await updateDoc(doc(chatRef(roomId), message.id), {
    [`reactions.${u}`]: current === token ? deleteField() : token,
  }).catch(() => {});
}

/// 今日の記録を、参加中の全プライベート港のチャットに自動の行として流す。
/// 空白明け(gapDays >= 2)は「帰還」— このアプリが一番祝いたい行。
export async function publishChatLog(input: {
  item: StudyItem;
  minutes: number;
  gapDays: number;
}): Promise<void> {
  const u = auth.currentUser?.uid;
  if (!u) return;
  const rooms = await fetchRooms().catch(() => [] as HarborRoom[]);
  if (rooms.length === 0) return;
  const isReturn = input.gapDays >= 2;
  const data = {
    uid: u,
    kind: isReturn ? "return" : "landfall",
    itemName: input.item.name.slice(0, 60),
    itemStyle: input.item.styleToken,
    itemSymbol: input.item.symbolToken,
    minutes: Math.min(input.minutes, 6000),
    ...(isReturn ? { gapDays: input.gapDays } : {}),
    createdAt: serverTimestamp(),
    reactions: {},
  };
  for (const room of rooms) {
    await addDoc(chatRef(room.id), data).catch(() => {});
  }
}

/// 今日より前で最後に学んだ日からの空白日数。今日が「何日ぶりの航海」かを決める。
export function gapDaysBeforeToday(days: StudyDay[]): number {
  const today = startOfDay(new Date());
  let last: Date | null = null;
  for (const d of days) {
    const dd = startOfDay(d.date);
    if (dd < today && (!last || dd > last)) last = dd;
  }
  if (!last) return 0;
  return Math.round((today.getTime() - last.getTime()) / 86400000);
}

// ---- 通報・ブロック ----

export async function reportUser(
  roomId: string,
  targetUid: string,
  messageId?: string,
): Promise<void> {
  const u = uid();
  await addDoc(collection(db, "reports"), {
    reporterUid: u,
    roomId,
    targetUid,
    ...(messageId ? { messageId } : {}),
    createdAt: serverTimestamp(),
  });
}

export async function loadBlocked(): Promise<Set<string>> {
  const u = auth.currentUser?.uid;
  if (!u) return new Set();
  const snap = await getDocs(collection(db, "users", u, "blocks")).catch(() => null);
  return new Set(snap?.docs.map((d) => d.id) ?? []);
}

export async function blockUser(targetUid: string): Promise<void> {
  const u = uid();
  await setDoc(doc(db, "users", u, "blocks", targetUid), { createdAt: serverTimestamp() });
}

// ---- アカウント削除時の後始末 ----

/// 全ての港から自分の痕跡を消し、users/{uid} 配下も空にする。
export async function deleteEverything(): Promise<void> {
  const u = uid();
  const rooms = await fetchRooms().catch(() => [] as HarborRoom[]);
  for (const room of rooms) await leaveRoom(room.id);
  await leaveAllPublic().catch(() => {});
  for (const sub of ["items", "sessions", "days", "destinations", "blocks"]) {
    const snap = await getDocs(collection(db, "users", u, sub)).catch(() => null);
    for (const d of snap?.docs ?? []) await deleteDoc(d.ref).catch(() => {});
  }
}
