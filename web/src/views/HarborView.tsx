import {
  Component,
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import {
  CHAT_REACTIONS,
  HarborError,
  PUBLIC_HARBORS,
  blockUser,
  cachedPublicJoined,
  createRoom,
  deleteChat,
  fetchMembers,
  fetchPublicJoined,
  fetchRooms,
  joinPublic,
  joinRoom,
  leavePublic,
  leaveRoom,
  listenChat,
  loadBlocked,
  reactChat,
  reportUser,
  sendChat,
  type ChatMessage,
  type HarborMember,
  type HarborRoom,
  type PublicHarborInfo,
} from "../harbor";
import type { UserData } from "../data";
import { demoHarborMembers, demoRoom, isDemo } from "../demo";
import { PlayerProfile } from "../profile";
import { STYLE_COLORS, normalizeStyle, normalizeSymbol, trimAll } from "../types";
import { PlayerAvatar, TileSymbolSvg } from "../symbols";
import { ProfileEditor } from "./ProfileEditor";
import { MemberTrace } from "./MemberTrace";
import { Modal, askConfirm, showToast } from "../overlays";
import { chatLandfallLine, chatReturnLine, t } from "../i18n";

// three.js を含む「みんなの海」は重いので、プライベートの港を開いたときだけ読み込む。
const HarborWorld = lazy(() => import("../three/HarborWorld"));

/// WebGLが使えるか(一度だけ判定)。使えない環境では3Dを出さない。
let webglCache: boolean | null = null;
function canUseWebGL(): boolean {
  if (webglCache !== null) return webglCache;
  try {
    const c = document.createElement("canvas");
    webglCache = Boolean(
      window.WebGLRenderingContext && (c.getContext("webgl2") || c.getContext("webgl")),
    );
  } catch {
    webglCache = false;
  }
  return webglCache;
}

/// 3Dの描画に失敗したら、何も表示しない(港の他の機能はそのまま)。
class HarborWorldBoundary extends Component<{ children?: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? null : this.props.children;
  }
}

type HarborNav =
  | { type: "root" }
  | { type: "public"; harbor: PublicHarborInfo }
  | { type: "room"; roomId: string }
  | {
      type: "member";
      root: "rooms" | "publicHarbors";
      containerId: string;
      member: HarborMember;
      back: HarborNav;
    };

function errText(e: unknown): string {
  if (e instanceof HarborError) {
    switch (e.code) {
      case "roomFull":
        return t("errRoomFull");
      case "tooManyRooms":
        return t("errTooManyRooms");
      case "alreadyOwnsRoom":
        return t("errAlreadyOwns");
      case "roomNotFound":
        return t("errRoomNotFound");
      default:
        return t("errGeneric");
    }
  }
  return t("errGeneric");
}

export function HarborView({ uid, data }: { uid: string; data: UserData }) {
  const [nav, setNav] = useState<HarborNav>({ type: "root" });
  const [rooms, setRooms] = useState<HarborRoom[]>([]);
  const [publicJoined, setPublicJoined] = useState<Set<string>>(cachedPublicJoined());
  const [blocked, setBlocked] = useState<Set<string>>(new Set());
  const [editingProfile, setEditingProfile] = useState(false);
  const [profileTick, setProfileTick] = useState(0);

  const reload = useCallback(async () => {
    // デモ(#demo)はFirestoreに触れず、見本の港をひとつ見せる。
    if (isDemo) {
      setRooms([demoRoom()]);
      return;
    }
    const [r, p, b] = await Promise.all([
      fetchRooms().catch(() => [] as HarborRoom[]),
      fetchPublicJoined().catch(() => cachedPublicJoined()),
      loadBlocked(),
    ]);
    setRooms(r);
    setPublicJoined(p);
    setBlocked(b);
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  if (nav.type === "member") {
    return (
      <MemberTrace
        root={nav.root}
        containerId={nav.containerId}
        member={nav.member}
        onBack={() => setNav(nav.back)}
      />
    );
  }

  if (nav.type === "public") {
    return (
      <PublicDetail
        uid={uid}
        harbor={nav.harbor}
        joined={publicJoined.has(nav.harbor.slug)}
        blocked={blocked}
        data={data}
        onBack={() => {
          setNav({ type: "root" });
          void reload();
        }}
        onOpenMember={(member) =>
          setNav({
            type: "member",
            root: "publicHarbors",
            containerId: nav.harbor.slug,
            member,
            back: nav,
          })
        }
        onBlockedChanged={(b) => setBlocked(b)}
      />
    );
  }

  if (nav.type === "room") {
    const room = rooms.find((r) => r.id === nav.roomId);
    if (!room) {
      setNav({ type: "root" });
      return null;
    }
    return (
      <RoomDetail
        uid={uid}
        room={room}
        blocked={blocked}
        onBack={() => {
          setNav({ type: "root" });
          void reload();
        }}
        onOpenMember={(member) =>
          setNav({ type: "member", root: "rooms", containerId: room.id, member, back: nav })
        }
        onBlockedChanged={(b) => setBlocked(b)}
      />
    );
  }

  return (
    <HarborRoot
      key={profileTick}
      rooms={rooms}
      publicJoined={publicJoined}
      data={data}
      onOpenPublic={(harbor) => setNav({ type: "public", harbor })}
      onOpenRoom={(roomId) => setNav({ type: "room", roomId })}
      onEditProfile={() => setEditingProfile(true)}
      onChanged={reload}
      editingProfile={editingProfile}
      onCloseProfile={() => {
        setEditingProfile(false);
        setProfileTick((n) => n + 1);
      }}
    />
  );
}

// ---- ルート(一覧) ----

function HarborRoot({
  rooms,
  publicJoined,
  data,
  onOpenPublic,
  onOpenRoom,
  onEditProfile,
  onChanged,
  editingProfile,
  onCloseProfile,
}: {
  rooms: HarborRoom[];
  publicJoined: Set<string>;
  data: UserData;
  onOpenPublic: (harbor: PublicHarborInfo) => void;
  onOpenRoom: (roomId: string) => void;
  onEditProfile: () => void;
  onChanged: () => Promise<void>;
  editingProfile: boolean;
  onCloseProfile: () => void;
}) {
  const [creating, setCreating] = useState(false);
  const [joining, setJoining] = useState(false);
  const cardStyle = STYLE_COLORS[normalizeStyle(PlayerProfile.styleToken)];

  return (
    <div>
      {/* プレイヤーカード */}
      <button
        className="player-card player-card-button"
        style={{ background: cardStyle.bg, color: cardStyle.fg }}
        onClick={onEditProfile}
      >
        <PlayerAvatar
          styleToken={PlayerProfile.styleToken}
          symbolToken={PlayerProfile.symbolToken}
          size={56}
        />
        <div className="player-card-texts">
          <div className="player-card-name">{PlayerProfile.displayName}</div>
          {PlayerProfile.resolve && (
            <div className="player-card-resolve">{PlayerProfile.resolve}</div>
          )}
        </div>
        <span className="player-card-edit">{t("edit")}</span>
      </button>

      {/* パブリック */}
      <p className="section-label">{t("publicSection")}</p>
      <div className="rows">
        {PUBLIC_HARBORS.map((harbor) => {
          const style = STYLE_COLORS[normalizeStyle(harbor.styleToken)];
          return (
            <button key={harbor.slug} className="row row-button" onClick={() => onOpenPublic(harbor)}>
              <span className="harbor-tile" style={{ background: style.bg }}>
                <TileSymbolSvg
                  symbol={normalizeSymbol(harbor.symbolToken)}
                  fg={style.fg}
                  bg={style.bg}
                />
              </span>
              <div className="row-main">
                <div className="row-title">{t(harbor.titleKey)}</div>
                <div className="row-sub">{t(harbor.taglineKey)}</div>
              </div>
              {publicJoined.has(harbor.slug) && (
                <span className="badge">{t("inHarbor")}</span>
              )}
              <span className="chevron">›</span>
            </button>
          );
        })}
      </div>

      {/* プライベート */}
      <p className="section-label">{t("privateSection")}</p>
      {rooms.length > 0 && (
        <div className="rows">
          {rooms.map((room) => (
            <button key={room.id} className="row row-button" onClick={() => onOpenRoom(room.id)}>
              <div className="row-main">
                <div className="row-title">{room.name}</div>
                <div className="row-sub">
                  {room.memberIds.length}/4 · {room.id}
                </div>
              </div>
              <span className="chevron">›</span>
            </button>
          ))}
        </div>
      )}
      <div className="chip-row" style={{ marginTop: 12 }}>
        <button className="chip" onClick={() => setCreating(true)}>
          {t("openHarbor")}
        </button>
        <button className="chip" onClick={() => setJoining(true)}>
          {t("joinByCode")}
        </button>
      </div>

      {creating && (
        <CreateRoomDialog
          data={data}
          onClose={async (changed) => {
            setCreating(false);
            if (changed) await onChanged();
          }}
        />
      )}
      {joining && (
        <JoinRoomDialog
          data={data}
          onClose={async (changed) => {
            setJoining(false);
            if (changed) await onChanged();
          }}
        />
      )}
      {editingProfile && <ProfileEditor onClose={onCloseProfile} />}
    </div>
  );
}

function CreateRoomDialog({
  data,
  onClose,
}: {
  data: UserData;
  onClose: (changed: boolean) => void;
}) {
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [working, setWorking] = useState(false);

  const trimmed = trimAll(name);
  const create = async () => {
    if (!trimmed || working) return;
    setWorking(true);
    try {
      await createRoom(trimmed, data);
      onClose(true);
    } catch (e) {
      setError(errText(e));
      setWorking(false);
    }
  };

  return (
    <Modal onClose={() => onClose(false)}>
      <>
        <h2 className="dialog-title">{t("openHarbor")}</h2>
        <p className="section-label">{t("harborName")}</p>
        <input
          className="field"
          value={name}
          onChange={(e) => setName(e.target.value)}
          maxLength={80}
          autoFocus
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.nativeEvent.isComposing && trimmed) void create();
          }}
        />
        {error && <p className="harbor-error">{error}</p>}
        <div style={{ height: 24 }} />
        <button className="primary-button" onClick={create} disabled={!trimmed || working}>
          {t("create")}
        </button>
      </>
    </Modal>
  );
}

function JoinRoomDialog({
  data,
  onClose,
}: {
  data: UserData;
  onClose: (changed: boolean) => void;
}) {
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [working, setWorking] = useState(false);

  const join = async () => {
    if (code.trim().length < 6 || working) return;
    setWorking(true);
    try {
      await joinRoom(code, data);
      onClose(true);
    } catch (e) {
      setError(errText(e));
      setWorking(false);
    }
  };

  return (
    <Modal onClose={() => onClose(false)}>
      <>
        <h2 className="dialog-title">{t("joinByCode")}</h2>
        <p className="section-label">{t("inviteCode")}</p>
        <input
          className="field code-field"
          value={code}
          onChange={(e) => setCode(e.target.value.toUpperCase())}
          placeholder={t("codePlaceholder")}
          maxLength={6}
          autoCapitalize="characters"
          autoCorrect="off"
          autoFocus
        />
        {error && <p className="harbor-error">{error}</p>}
        <div style={{ height: 24 }} />
        <button
          className="primary-button"
          onClick={join}
          disabled={code.trim().length < 6 || working}
        >
          {t("join")}
        </button>
      </>
    </Modal>
  );
}

// ---- パブリックの港の中 ----

function PublicDetail({
  uid,
  harbor,
  joined,
  blocked,
  data,
  onBack,
  onOpenMember,
  onBlockedChanged,
}: {
  uid: string;
  harbor: PublicHarborInfo;
  joined: boolean;
  blocked: Set<string>;
  data: UserData;
  onBack: () => void;
  onOpenMember: (member: HarborMember) => void;
  onBlockedChanged: (blocked: Set<string>) => void;
}) {
  const [members, setMembers] = useState<HarborMember[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [isJoined, setIsJoined] = useState(joined);
  const [working, setWorking] = useState(false);
  const [editingProfile, setEditingProfile] = useState(false);
  const style = STYLE_COLORS[normalizeStyle(harbor.styleToken)];

  const reload = useCallback(async () => {
    setMembers(await fetchMembers("publicHarbors", harbor.slug));
    setLoaded(true);
  }, [harbor.slug]);

  useEffect(() => {
    void reload();
  }, [reload]);

  const join = async () => {
    if (working) return;
    // 名前が未設定のまま公開の場に「船乗り」で並ばないよう、先にカードを整えてもらう。
    if (!PlayerProfile.name) {
      showToast(t("setNameFirst"));
      setEditingProfile(true);
      return;
    }
    setWorking(true);
    try {
      await joinPublic(harbor.slug, data);
      setIsJoined(true);
      showToast(t("joinedToast"));
      await reload();
    } catch {
      showToast(t("errGeneric"));
    } finally {
      setWorking(false);
    }
  };

  const leave = async () => {
    if (working) return;
    const ok = await askConfirm({
      title: t("leaveHarbor"),
      message: t("leavePublicConfirm"),
      confirmLabel: t("leaveHarbor"),
      danger: true,
    });
    if (!ok) return;
    setWorking(true);
    try {
      await leavePublic(harbor.slug);
      setIsJoined(false);
      showToast(t("leftToast"));
      await reload();
    } finally {
      setWorking(false);
    }
  };

  const report = async (member: HarborMember) => {
    const ok = await askConfirm({
      title: t("reportSailorTitle"),
      message: t("reportNote"),
      confirmLabel: t("report"),
      danger: true,
    });
    if (!ok) return;
    await reportUser(harbor.slug, member.id).catch(() => {});
    showToast(t("sentReport"));
  };

  const block = async (member: HarborMember) => {
    const ok = await askConfirm({
      title: t("blockTitle"),
      message: t("blockNote"),
      confirmLabel: t("block"),
      danger: true,
    });
    if (!ok) return;
    await blockUser(member.id).catch(() => {});
    const next = new Set(blocked);
    next.add(member.id);
    onBlockedChanged(next);
    showToast(t("blockedToast"));
  };

  const visible = members.filter((m) => !blocked.has(m.id));

  return (
    <div>
      <button className="quiet-button" onClick={onBack}>
        ‹ {t("back")}
      </button>

      <div className="member-head">
        <span className="harbor-tile harbor-tile-lg" style={{ background: style.bg }}>
          <TileSymbolSvg symbol={normalizeSymbol(harbor.symbolToken)} fg={style.fg} bg={style.bg} />
        </span>
        <div>
          <div className="page-title">{t(harbor.titleKey)}</div>
          <div className="page-sub">{t(harbor.taglineKey)}</div>
        </div>
      </div>

      {isJoined ? (
        <button className="quiet-button" onClick={leave} disabled={working}>
          {t("leaveHarbor")}
        </button>
      ) : (
        <div style={{ marginTop: 8 }}>
          <button className="primary-button" onClick={join} disabled={working}>
            {t("joinHarbor")}
          </button>
          <p className="page-sub" style={{ marginTop: 10 }}>
            {t("joinDisclosure")}
          </p>
        </div>
      )}

      <p className="section-label">{t("sailors")}</p>
      {!loaded ? (
        <p className="empty-note">{t("loading")}</p>
      ) : visible.length === 0 ? (
        <p className="empty-note">{t("noSailors")}</p>
      ) : (
        <div className="rows">
          {visible.map((member) => (
            <div key={member.id} className="row">
              <button className="row-tap" onClick={() => onOpenMember(member)}>
                <PlayerAvatar
                  styleToken={member.styleToken}
                  symbolToken={member.symbolToken}
                  size={38}
                />
                <div className="row-main">
                  <div className="row-title">
                    {member.displayName}
                    {member.id === uid && <span className="you-tag">{t("you")}</span>}
                  </div>
                  {member.resolve && <div className="row-sub">{member.resolve}</div>}
                </div>
                <span className="chevron">›</span>
              </button>
              {member.id !== uid && (
                <MemberActions onReport={() => report(member)} onBlock={() => block(member)} />
              )}
            </div>
          ))}
        </div>
      )}

      {editingProfile && <ProfileEditor onClose={() => setEditingProfile(false)} />}
    </div>
  );
}

function MemberActions({ onReport, onBlock }: { onReport: () => void; onBlock: () => void }) {
  const [open, setOpen] = useState(false);
  return (
    <span className="member-actions">
      <button className="quiet-button" onClick={() => setOpen((v) => !v)} aria-label="actions">
        …
      </button>
      {open && (
        <>
          <button
            className="quiet-button"
            onClick={() => {
              setOpen(false);
              onReport();
            }}
          >
            {t("report")}
          </button>
          <button
            className="quiet-button danger-text"
            onClick={() => {
              setOpen(false);
              onBlock();
            }}
          >
            {t("block")}
          </button>
        </>
      )}
    </span>
  );
}

// ---- プライベートの港の中(メンバー+チャット) ----

function RoomDetail({
  uid,
  room,
  blocked,
  onBack,
  onOpenMember,
  onBlockedChanged,
}: {
  uid: string;
  room: HarborRoom;
  blocked: Set<string>;
  onBack: () => void;
  onOpenMember: (member: HarborMember) => void;
  onBlockedChanged: (blocked: Set<string>) => void;
}) {
  const [members, setMembers] = useState<HarborMember[]>([]);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [copied, setCopied] = useState(false);
  const endRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    // デモ(#demo)は見本のメンバーだけ(チャットは購読しない)。
    if (isDemo) {
      setMembers(demoHarborMembers());
      return;
    }
    void fetchMembers("rooms", room.id).then(setMembers);
    return listenChat(room.id, setMessages);
  }, [room.id]);

  useEffect(() => {
    endRef.current?.scrollIntoView({ block: "end" });
  }, [messages.length]);

  const memberById = new Map(members.map((m) => [m.id, m]));
  const nameOf = (id: string) => memberById.get(id)?.displayName ?? t("sailor");
  const visibleMessages = messages.filter((m) => !blocked.has(m.uid));

  const send = async () => {
    const text = draft.trim();
    if (!text) return;
    setDraft("");
    // 送信後もフォーカスを保ち、続けて書けるようにする。
    inputRef.current?.focus();
    await sendChat(room.id, text).catch(() => showToast(t("errGeneric")));
  };

  const copyCode = async () => {
    await navigator.clipboard.writeText(room.id).catch(() => {});
    setCopied(true);
    showToast(t("copied"));
    setTimeout(() => setCopied(false), 1600);
  };

  const leave = async () => {
    const ok = await askConfirm({
      title: t("leaveHarbor"),
      message: t("leaveRoomConfirm"),
      confirmLabel: t("leaveHarbor"),
      danger: true,
    });
    if (!ok) return;
    await leaveRoom(room.id);
    showToast(t("leftToast"));
    onBack();
  };

  const reportMsg = async (m: ChatMessage) => {
    const ok = await askConfirm({
      title: t("reportMessageTitle"),
      message: t("reportNote"),
      confirmLabel: t("report"),
      danger: true,
    });
    if (!ok) return;
    await reportUser(room.id, m.uid, m.id).catch(() => {});
    showToast(t("sentReport"));
  };

  const blockMsgAuthor = async (m: ChatMessage) => {
    const ok = await askConfirm({
      title: t("blockTitle"),
      message: t("blockNote"),
      confirmLabel: t("block"),
      danger: true,
    });
    if (!ok) return;
    await blockUser(m.uid).catch(() => {});
    const next = new Set(blocked);
    next.add(m.uid);
    onBlockedChanged(next);
    showToast(t("blockedToast"));
  };

  return (
    <div>
      <button className="quiet-button" onClick={onBack}>
        ‹ {t("back")}
      </button>

      <div className="member-head">
        <div style={{ flex: 1 }}>
          <div className="page-title">{room.name}</div>
          <div className="page-sub">
            {t("inviteCode")}: {room.id}{" "}
            <button className="quiet-button" onClick={copyCode}>
              {copied ? t("copied") : t("copy")}
            </button>
          </div>
        </div>
      </div>

      {/* みんなの海: メンバー全員の船が同じ夜の海で島へ並走する3D。
          船をタップするとその人の軌跡へ。失敗時は静かに何も出さない。 */}
      {canUseWebGL() && (
        <HarborWorldBoundary>
          <Suspense fallback={<div className="harbor-world-fallback" />}>
            <HarborWorld room={room} members={members} onSelectMember={onOpenMember} />
          </Suspense>
        </HarborWorldBoundary>
      )}

      {/* メンバー(タップで軌跡へ) */}
      <div className="chip-row" style={{ marginTop: 8 }}>
        {members.map((m) => (
          <button key={m.id} className="member-chip" onClick={() => onOpenMember(m)}>
            <PlayerAvatar styleToken={m.styleToken} symbolToken={m.symbolToken} size={30} />
            <span>{m.displayName}</span>
          </button>
        ))}
      </div>

      {/* チャット */}
      <p className="section-label">{t("chatTitle")}</p>
      <div className="chat-box">
        {visibleMessages.length === 0 && (
          <p className="empty-note">{t("chatEmpty")}</p>
        )}
        {visibleMessages.map((m) => (
          <ChatRow
            key={m.id}
            uid={uid}
            message={m}
            name={nameOf(m.uid)}
            onReact={(token) => void reactChat(room.id, m, token)}
            onDelete={
              m.uid === uid
                ? async () => {
                    if (
                      await askConfirm({
                        title: t("deleteSessionConfirm"),
                        confirmLabel: t("delete"),
                        danger: true,
                      })
                    ) {
                      void deleteChat(room.id, m.id);
                    }
                  }
                : undefined
            }
            onReport={m.uid !== uid ? () => void reportMsg(m) : undefined}
            onBlock={m.uid !== uid ? () => void blockMsgAuthor(m) : undefined}
          />
        ))}
        <div ref={endRef} />
      </div>
      <div className="chat-input">
        <input
          ref={inputRef}
          className="field"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder={t("chatPlaceholder")}
          maxLength={500}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.nativeEvent.isComposing) void send();
          }}
        />
        <button className="chip" onClick={send} disabled={!draft.trim()}>
          {t("send")}
        </button>
      </div>

      <div style={{ marginTop: 28 }}>
        <button className="quiet-button danger-text" onClick={leave}>
          {t("leaveHarbor")}
        </button>
      </div>
    </div>
  );
}

function ChatRow({
  uid,
  message,
  name,
  onReact,
  onDelete,
  onReport,
  onBlock,
}: {
  uid: string;
  message: ChatMessage;
  name: string;
  onReact: (token: string) => void;
  onDelete?: () => void;
  onReport?: () => void;
  onBlock?: () => void;
}) {
  const [actionsOpen, setActionsOpen] = useState(false);
  const mine = message.uid === uid;

  const counts = new Map<string, number>();
  for (const token of Object.values(message.reactions)) {
    counts.set(token, (counts.get(token) ?? 0) + 1);
  }
  const myReaction = message.reactions[uid];

  const reactions = (
    <div className="chat-reactions">
      {CHAT_REACTIONS.map((token) => {
        const style = STYLE_COLORS[normalizeStyle("midnight")];
        const count = counts.get(token) ?? 0;
        return (
          <button
            key={token}
            className={`reaction${myReaction === token ? " selected" : ""}`}
            onClick={() => onReact(token)}
            aria-label={token}
          >
            <span className="reaction-symbol">
              <TileSymbolSvg
                symbol={normalizeSymbol(token)}
                fg="currentColor"
                bg={style.bg}
              />
            </span>
            {count > 0 && <span>{count}</span>}
          </button>
        );
      })}
    </div>
  );

  if (message.kind !== "text") {
    const line =
      message.kind === "return"
        ? chatReturnLine(name, message.gapDays ?? 0)
        : chatLandfallLine(name, message.itemName ?? "—", message.minutes ?? 0);
    return (
      <div className={`chat-auto${message.kind === "return" ? " return" : ""}`}>
        <span>{line}</span>
        {reactions}
      </div>
    );
  }

  return (
    <div className={`chat-msg${mine ? " mine" : ""}`}>
      {!mine && <div className="chat-name">{name}</div>}
      <div
        className="chat-bubble"
        onClick={() => setActionsOpen((v) => !v)}
        role="button"
        tabIndex={0}
      >
        {message.text}
      </div>
      {actionsOpen && (
        <div className="chat-actions">
          {onDelete && (
            <button className="quiet-button danger-text" onClick={onDelete}>
              {t("delete")}
            </button>
          )}
          {onReport && (
            <button className="quiet-button" onClick={onReport}>
              {t("report")}
            </button>
          )}
          {onBlock && (
            <button className="quiet-button danger-text" onClick={onBlock}>
              {t("block")}
            </button>
          )}
        </div>
      )}
      {reactions}
    </div>
  );
}
