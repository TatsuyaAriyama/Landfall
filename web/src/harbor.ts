import {
  addDoc,
  arrayRemove,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  limitToLast,
  onSnapshot,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} from "firebase/firestore";
import { storage } from "./storage";
import { auth, db } from "./firebase";
import { PlayerProfile } from "./profile";
import { serviceStartDay } from "./since";
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
  // 航海のはじまり(yyyy-MM-dd)。古いクライアントが書いたカードには無い。
  sinceDay?: string;
  // 船の見た目(部位id)。古いクライアントが書いたカードには無い。
  boatSail?: string;
  boatJib?: string;
  boatHull?: string;
  boatStripe?: string;
  boatFlag?: string;
}

// 港を開いている間だけ共有する、一時的な航海士の状態。
// updatedAt が古いものは描画側で無視し、タブ終了時の削除に失敗しても残像を残さない。
export const HARBOR_PRESENCE_POSES = [
  "idle",
  "walk",
  "pickupRod",
  "equipRod",
  "holdRod",
  "walkRod",
  "stowRod",
  "hail",
  "raise",
  "point",
  "lookout",
  "rest",
  "read",
] as const;
export type HarborPresencePose = (typeof HARBOR_PRESENCE_POSES)[number];

export interface HarborPresence {
  uid: string;
  x: number;
  z: number;
  yaw: number;
  pose: HarborPresencePose;
  aboard: boolean;
  /** 共同航海レーン内での左右の操船位置。 */
  sailX: number;
  fishingRod: boolean;
  emoteSeq: number;
  updatedAt: Date;
}

/// 航海のはじまり(yyyy-MM-dd)の読み取り。書式が違うもの・実在しない日は捨てる。
export function parseSinceDay(value: unknown): string | undefined {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return undefined;
  return sinceDayDate(value) ? value : undefined;
}

/// yyyy-MM-dd を端末ローカルの日付に戻す。実在しない日(2025-02-30 など)は null。
/// 書いた人の暦での「日」なので、時差のある相手が見ても日付はずれない。
export function sinceDayDate(sinceDay: string): Date | null {
  const [y, m, d] = sinceDay.split("-").map(Number);
  const date = new Date(y, m - 1, d);
  if (date.getFullYear() !== y || date.getMonth() !== m - 1 || date.getDate() !== d) return null;
  return date;
}

export interface SharedSession {
  day: number;
  minutes: number;
  date?: Date; // 記録時刻(ペイロードに含まれる場合のみ)
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
}

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

function roomFromDoc(id: string, value: Record<string, unknown>): HarborRoom {
  return {
    id,
    name: String(value.name ?? ""),
    memberIds: Array.isArray(value.memberIds)
      ? value.memberIds.filter((memberId): memberId is string => typeof memberId === "string")
      : [],
    ownerUid: typeof value.ownerUid === "string" ? value.ownerUid : undefined,
  };
}

export async function fetchRooms(): Promise<HarborRoom[]> {
  const u = uid();
  const snap = await getDocs(
    query(collection(db, "rooms"), where("memberIds", "array-contains", u)),
  );
  return snap.docs.map((d) => roomFromDoc(d.id, d.data()));
}

/// 参加中の港と人数をリアルタイムで反映する。
/// 招待された側の参加・退港が、既に港を開いている端末にも再読込なしで届く。
export function listenRooms(
  cb: (rooms: HarborRoom[]) => void,
  onError?: () => void,
): () => void {
  const u = uid();
  return onSnapshot(
    query(collection(db, "rooms"), where("memberIds", "array-contains", u)),
    (snap) => cb(snap.docs.map((d) => roomFromDoc(d.id, d.data()))),
    () => onError?.(),
  );
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
  const code = normalizeRoomCode(rawCode);
  if (code.length !== 6) throw new HarborError("roomNotFound");
  const ref = doc(db, "rooms", code);
  const rooms = await fetchRooms();
  const alreadyJoined = rooms.some((room) => room.id === code);
  if (!alreadyJoined && rooms.length >= ROOM_MAX_JOINED) {
    throw new HarborError("tooManyRooms");
  }

  // 読み取り→更新を一つのトランザクションにする。二人が最後の一席へ同時に
  // 入ろうとしても、再試行時に最新人数を読み直して4人を超えない。
  let addedMembership = false;
  await runTransaction(db, async (transaction) => {
    // トランザクションは競合時に同じコールバックを再実行する。
    addedMembership = false;
    const snap = await transaction.get(ref);
    if (!snap.exists()) throw new HarborError("roomNotFound");
    const rawMembers: unknown = snap.data().memberIds;
    const members = Array.isArray(rawMembers)
      ? rawMembers.filter((memberId: unknown): memberId is string => typeof memberId === "string")
      : [];
    if (members.includes(u)) return;
    if (members.length >= ROOM_MAX_MEMBERS) throw new HarborError("roomFull");
    transaction.update(ref, { memberIds: [...members, u] });
    addedMembership = true;
  });

  try {
    await joinedSetup("rooms", code, data);
  } catch (error) {
    // メンバーカードの作成に失敗したとき、人数だけ増えた「見えない参加者」を
    // 港に残さない。元から参加済みだった場合は所属を触らない。
    if (addedMembership) {
      await updateDoc(ref, { memberIds: arrayRemove(u) }).catch(() => {});
    }
    throw error;
  }
}

/// 招待コード入力。区切りを含む貼り付けにも耐え、実際に発行する文字だけを残す。
export function normalizeRoomCode(rawCode: string): string {
  return rawCode.toUpperCase().replace(/[^A-HJ-NP-Z2-9]/g, "").slice(0, 6);
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
  storage.set(JOINED_CACHE_KEY, JSON.stringify([...found].sort()));
  return found;
}

export function cachedPublicJoined(): Set<string> {
  try {
    return new Set(JSON.parse(storage.get(JOINED_CACHE_KEY) ?? "[]") as string[]);
  } catch {
    return new Set();
  }
}

export async function joinPublic(slug: string, data: PublishSource): Promise<void> {
  await joinedSetup("publicHarbors", slug, data);
  const joined = cachedPublicJoined();
  joined.add(slug);
  storage.set(JOINED_CACHE_KEY, JSON.stringify([...joined].sort()));
}

export async function leavePublic(slug: string): Promise<void> {
  const u = uid();
  const memberRef = doc(db, "publicHarbors", slug, "members", u);
  const months = await getDocs(collection(memberRef, "months")).catch(() => null);
  for (const m of months?.docs ?? []) await deleteDoc(m.ref).catch(() => {});
  await deleteDoc(memberRef).catch(() => {});
  const joined = cachedPublicJoined();
  joined.delete(slug);
  storage.set(JOINED_CACHE_KEY, JSON.stringify([...joined].sort()));
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
    ...PlayerProfile.harborProfileData(serviceStartDay(data.days, data.sessions)),
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
/// sinceDay(使い始めた日)は画面側で serviceStartDay から出したものを渡す。
export async function pushProfileEverywhere(sinceDay?: Date | null): Promise<void> {
  const u = uid();
  const data = PlayerProfile.harborProfileData(sinceDay);
  const rooms = await fetchRooms().catch(() => [] as HarborRoom[]);
  for (const room of rooms) {
    await setDoc(doc(db, "rooms", room.id, "members", u), data, { merge: true }).catch(() => {});
  }
  for (const slug of cachedPublicJoined()) {
    await setDoc(doc(db, "publicHarbors", slug, "members", u), data, { merge: true }).catch(
      () => {},
    );
  }
}

// ---- メンバーと月間記録の閲覧 ----

function membersFromDocs(
  docs: { id: string; data: () => Record<string, unknown> }[],
): HarborMember[] {
  const str = (value: unknown) => (typeof value === "string" ? value : undefined);
  return docs.map((d) => {
    const v = d.data();
    return {
      id: d.id,
      displayName: String(v.displayName ?? ""),
      styleToken: String(v.styleToken ?? "midnight"),
      symbolToken: String(v.symbolToken ?? "phoenix"),
      resolve: String(v.resolve ?? ""),
      sinceDay: parseSinceDay(v.sinceDay),
      boatSail: str(v.boatSail),
      boatJib: str(v.boatJib),
      boatHull: str(v.boatHull),
      boatStripe: str(v.boatStripe),
      boatFlag: str(v.boatFlag),
    };
  });
}

export async function fetchMembers(
  root: "rooms" | "publicHarbors",
  id: string,
): Promise<HarborMember[]> {
  const snap = await getDocs(
    query(collection(db, root, id, "members"), orderBy("joinedAt", "desc"), limit(200)),
  ).catch(() => null);
  return snap ? membersFromDocs(snap.docs) : [];
}

/// 港内の船をリアルタイムで保つ。初回以降に増えたメンバーは画面側で
/// 入港アニメーションへ渡し、退港したメンバーは購読結果から自然に消える。
export function listenMembers(
  root: "rooms" | "publicHarbors",
  id: string,
  cb: (members: HarborMember[]) => void,
  onError?: () => void,
): () => void {
  return onSnapshot(
    query(collection(db, root, id, "members"), orderBy("joinedAt", "desc"), limit(200)),
    (snap) => cb(membersFromDocs(snap.docs)),
    () => onError?.(),
  );
}

function presenceRef(roomId: string, memberId: string) {
  return doc(db, "rooms", roomId, "presence", memberId);
}

/// 同じ友人港を開いている航海士の位置・向き・仕草を購読する。
/// 最大4人の一時コレクションで、履歴や学習記録としては保存しない。
export function listenHarborPresence(
  roomId: string,
  cb: (presence: HarborPresence[]) => void,
): () => void {
  return onSnapshot(
    collection(db, "rooms", roomId, "presence"),
    (snap) => {
      cb(
        snap.docs.flatMap((presenceDoc) => {
          const value = presenceDoc.data();
          const pose = value.pose;
          if (
            typeof pose !== "string" ||
            !HARBOR_PRESENCE_POSES.includes(pose as HarborPresencePose)
          ) {
            return [];
          }
          return [{
            uid: presenceDoc.id,
            x: Number(value.x ?? 0),
            z: Number(value.z ?? 0),
            yaw: Number(value.yaw ?? 0),
            pose: pose as HarborPresencePose,
            aboard: value.aboard === true,
            sailX: Math.max(-0.75, Math.min(0.75, Number(value.sailX ?? 0))),
            fishingRod: value.fishingRod === true,
            emoteSeq:
              typeof value.emoteSeq === "number" ? Math.max(0, value.emoteSeq) : 0,
            updatedAt:
              value.updatedAt instanceof Timestamp
                ? value.updatedAt.toDate()
                : new Date(0),
          }];
        }),
      );
    },
    () => cb([]),
  );
}

export async function publishHarborPresence(
  roomId: string,
  state: Omit<HarborPresence, "uid" | "updatedAt">,
): Promise<void> {
  const currentUid = uid();
  await setDoc(presenceRef(roomId, currentUid), {
    x: state.x,
    z: state.z,
    yaw: state.yaw,
    pose: state.pose,
    aboard: state.aboard,
    sailX: Math.max(-0.75, Math.min(0.75, state.sailX)),
    fishingRod: state.fishingRod,
    emoteSeq: Math.max(0, Math.floor(state.emoteSeq)),
    updatedAt: serverTimestamp(),
  });
}

export async function clearHarborPresence(roomId: string): Promise<void> {
  const currentUid = auth.currentUser?.uid;
  if (!currentUid) return;
  await deleteDoc(presenceRef(roomId, currentUid));
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
      date: s.date instanceof Timestamp ? s.date.toDate() : undefined,
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
        ...(item || s.itemName
          ? {
              itemName: (item?.name ?? s.itemName ?? "").slice(0, 60),
              styleToken: item?.styleToken ?? s.itemStyle ?? "midnight",
              symbolToken: item?.symbolToken ?? s.itemSymbol ?? "compass",
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

// ---- 共同航海(rooms/{code}/voyage/current 単一ドキュメント) ----
// 目的地を決めると seed から海図(3航路)がひらき、選んだ航路を全員で進む。
// 航路の途中に嵐/海獣の海域があり(生成は voyageMap.ts、seed から決定的)、
// 全員の学習時間の合算=船団の位置。到着(arrivedAt)は一度きりの刻印。
// 進捗カウンタは持たない — 各メンバーの共有月間記録(members/{uid}/months)の
// sessions のうち date >= createdAt の minutes を全員分合算して導出する。

export const VOYAGE_MIN_MINUTES = 60;
export const VOYAGE_MAX_MINUTES = 600000;

export interface HarborVoyage {
  seed: number;
  targetMinutes: number;
  routeIndex: number; // 0..2(generateRoutes(seed) の添字)
  createdAt: Date;
  createdBy: string;
  arrivedAt?: Date;
}

function voyageRef(roomId: string) {
  return doc(db, "rooms", roomId, "voyage", "current");
}

function voyageFromData(v: Record<string, unknown>): HarborVoyage {
  return {
    seed: Number(v.seed ?? 0) >>> 0,
    targetMinutes: Number(v.targetMinutes ?? 0),
    routeIndex: Math.min(Math.max(Number(v.routeIndex ?? 0), 0), 2),
    createdAt: v.createdAt instanceof Timestamp ? v.createdAt.toDate() : new Date(),
    createdBy: String(v.createdBy ?? ""),
    arrivedAt: v.arrivedAt instanceof Timestamp ? v.arrivedAt.toDate() : undefined,
  };
}

export function listenVoyage(
  roomId: string,
  cb: (voyage: HarborVoyage | null) => void,
): () => void {
  return onSnapshot(
    voyageRef(roomId),
    (snap) => cb(snap.exists() ? voyageFromData(snap.data()) : null),
    () => cb(null),
  );
}

/// 一回きりの読み(起動時の戦利品チェックなどに使う)。
export async function fetchVoyage(roomId: string): Promise<HarborVoyage | null> {
  const snap = await getDoc(voyageRef(roomId)).catch(() => null);
  if (!snap || !snap.exists()) return null;
  return voyageFromData(snap.data());
}

export async function createVoyage(
  roomId: string,
  seed: number,
  routeIndex: number,
  targetMinutes: number,
): Promise<void> {
  const u = uid();
  const target = Math.min(
    Math.max(Math.round(targetMinutes), VOYAGE_MIN_MINUTES),
    VOYAGE_MAX_MINUTES,
  );
  await setDoc(voyageRef(roomId), {
    seed: seed >>> 0,
    targetMinutes: target,
    routeIndex: Math.min(Math.max(Math.round(routeIndex), 0), 2),
    createdAt: serverTimestamp(),
    createdBy: u,
  });
}

export async function deleteVoyage(roomId: string): Promise<void> {
  await deleteDoc(voyageRef(roomId));
}

/// 到着の刻印。合算 >= 目標 を見た閲覧者が1回だけ書く。すでに arrivedAt が
/// ある場合はルールで拒否される(並走した閲覧者の2回目は静かに失敗させる)。
export async function markVoyageArrived(roomId: string): Promise<void> {
  await updateDoc(voyageRef(roomId), { arrivedAt: serverTimestamp() });
}

/// 航海の進捗(分)。出航月〜当月の months ドキュメントだけを全メンバー分読み、
/// date >= createdAt のセッションを合算する(メンバー≤4なので読みは少ない)。
/// date が無い旧クライアントのセッションは day フィールドから日単位で概算する
/// (その日の始まりが createdAt の日の始まり以降なら含める。同日の出航前の
///  記録も拾い得るが、友人港の遊びなので寛容側に倒す)。
export async function voyageProgressMinutes(
  roomId: string,
  memberIds: string[],
  voyage: HarborVoyage,
): Promise<number> {
  const created = voyage.createdAt;
  const createdDayStart = new Date(
    created.getFullYear(),
    created.getMonth(),
    created.getDate(),
  );
  // 創設月〜当月の yyyy-MM 一覧(読みすぎ防止で直近24ヶ月に丸める。
  // 切るなら古い月 — 当月側を落とすと新規セッションが進捗に入らなくなる)。
  const months: string[] = [];
  const cursor = new Date(created.getFullYear(), created.getMonth(), 1);
  const now = new Date();
  const last = new Date(now.getFullYear(), now.getMonth(), 1);
  const floor = new Date(last.getFullYear(), last.getMonth() - 23, 1);
  if (cursor < floor) cursor.setTime(floor.getTime());
  while (cursor <= last) {
    months.push(`${cursor.getFullYear()}-${String(cursor.getMonth() + 1).padStart(2, "0")}`);
    cursor.setMonth(cursor.getMonth() + 1);
  }
  let total = 0;
  await Promise.all(
    memberIds.slice(0, ROOM_MAX_MEMBERS).map(async (memberId) => {
      for (const ym of months) {
        const month = await fetchMonth("rooms", roomId, memberId, ym);
        if (!month) continue;
        const [y, m] = ym.split("-").map(Number);
        for (const s of month.sessions) {
          if (s.minutes <= 0) continue;
          if (s.date) {
            if (s.date >= created) total += s.minutes;
          } else {
            // 旧セッション(dateなし): dayから日単位で概算。
            const dayDate = new Date(y, m - 1, s.day);
            if (dayDate >= createdDayStart) total += s.minutes;
          }
        }
      }
    }),
  );
  return total;
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
  for (const sub of ["items", "sessions", "days", "voyageLogs", "destinations", "blocks"]) {
    const snap = await getDocs(collection(db, "users", u, sub)).catch(() => null);
    for (const d of snap?.docs ?? []) await deleteDoc(d.ref).catch(() => {});
  }
}
