import { useEffect, useMemo, useState } from "react";
import { saveVoyageLog, type UserData } from "../data";
import { BoatGroup } from "../symbols";
import { boatProps } from "../boat";
import { lang, t, yearChartTitle } from "../i18n";
import { deleteDestination } from "../destinations";
import { askConfirm } from "../overlays";
import { dayId } from "../types";
import { storage } from "../storage";

// 航海誌。月ごとの共有カードではなく、一日ごとに自由な言葉を残す「航海日録」。
// 作業記録がない日も書けるため、StudyDay とは独立した voyageLogs に保存する。

export function LogbookView({ uid, data }: { uid: string; data: UserData }) {
  const [view, setView] = useState<"journal" | "year">("journal");
  return (
    <div>
      <div className="chip-row" style={{ marginBottom: 24 }}>
        <button
          className={`chip${view === "journal" ? " selected" : ""}`}
          onClick={() => setView("journal")}
        >
          {t("voyageJournal")}
        </button>
        <button
          className={`chip${view === "year" ? " selected" : ""}`}
          onClick={() => setView("year")}
        >
          {t("yearChart")}
        </button>
      </div>
      {view === "journal" ? (
        <VoyageJournal uid={uid} data={data} />
      ) : (
        <>
          <YearChart data={data} />
          <ReachedIslands uid={uid} data={data} />
        </>
      )}
    </div>
  );
}

function dateFromId(id: string): Date {
  return new Date(`${id}T12:00:00`);
}

function formatMinutes(total: number): string {
  const hours = Math.floor(total / 60);
  const minutes = total % 60;
  if (lang === "ja") {
    return `${hours > 0 ? `${hours}時間` : ""}${minutes}分`;
  }
  return `${hours > 0 ? `${hours}h ` : ""}${minutes}m`;
}

function VoyageJournal({ uid, data }: { uid: string; data: UserData }) {
  const [selectedId, setSelectedId] = useState(() => dayId(new Date()));
  const [archiveYear, setArchiveYear] = useState(() => new Date().getFullYear());
  const selectedDate = dateFromId(selectedId);
  const entry = data.voyageLogs.find((log) => log.id === selectedId);
  const draftKey = `voyage-log.draft.${uid}.${selectedId}`;
  const [draft, setDraft] = useState(
    () => storage.sessionGet(`voyage-log.draft.${uid}.${selectedId}`) ?? entry?.body ?? "",
  );
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [saveFailed, setSaveFailed] = useState(false);

  const archiveYears = useMemo(() => {
    const years = new Set(data.voyageLogs.map((log) => log.date.getFullYear()));
    years.add(selectedDate.getFullYear());
    return [...years].sort((a, b) => b - a);
  }, [data.voyageLogs, selectedDate]);
  const archiveLogs = useMemo(
    () => data.voyageLogs.filter((log) => log.date.getFullYear() === archiveYear),
    [archiveYear, data.voyageLogs],
  );

  useEffect(() => {
    setDraft(storage.sessionGet(draftKey) ?? entry?.body ?? "");
    setSaved(false);
    setSaveFailed(false);
  }, [draftKey, entry?.body]);

  const sessions = data.sessions.filter((session) => dayId(session.date) === selectedId);
  const totalMinutes = sessions.reduce((sum, session) => sum + session.minutes, 0);
  const itemNames = [
    ...new Set(
      sessions
        .map(
          (session) =>
            data.items.find((item) => item.id === session.itemUUID)?.name ??
            session.itemName,
        )
        .filter((name): name is string => Boolean(name)),
    ),
  ];
  const fullDate = new Intl.DateTimeFormat(lang, {
    year: "numeric",
    month: "long",
    day: "numeric",
    weekday: "short",
  }).format(selectedDate);

  const save = async () => {
    setSaving(true);
    setSaved(false);
    setSaveFailed(false);
    try {
      await saveVoyageLog(uid, selectedDate, draft);
      storage.sessionRemove(draftKey);
      setSaved(true);
    } catch {
      setSaveFailed(true);
    } finally {
      setSaving(false);
    }
  };

  const selectDate = (id: string) => {
    setSelectedId(id);
    setArchiveYear(dateFromId(id).getFullYear());
  };

  const remove = async () => {
    if (!entry || saving) return;
    if (
      !(await askConfirm({
        title: t("deleteVoyageJournalConfirm"),
        confirmLabel: t("delete"),
        danger: true,
      }))
    ) {
      return;
    }
    setSaving(true);
    setSaveFailed(false);
    try {
      await saveVoyageLog(uid, selectedDate, "");
      storage.sessionRemove(draftKey);
      setDraft("");
      setSaved(true);
    } catch {
      setSaveFailed(true);
    } finally {
      setSaving(false);
    }
  };

  return (
    <section className="voyage-journal">
      <header className="voyage-journal-heading">
        <div>
          <p className="section-label">{t("voyageJournal")}</p>
          <h2>{fullDate}</h2>
          <p>{t("voyageJournalIntro")}</p>
        </div>
        <input
          className="voyage-journal-date"
          type="date"
          value={selectedId}
          max={dayId(new Date())}
          onChange={(event) => selectDate(event.target.value)}
          aria-label={t("voyageJournal")}
        />
      </header>

      <div className="voyage-journal-weather">
        <span>{t("voyageJournalTime")}</span>
        <strong>{formatMinutes(totalMinutes)}</strong>
        {itemNames.length > 0 && <small>{itemNames.join(" · ")}</small>}
      </div>

      <label className="sr-only" htmlFor="voyage-journal-body">
        {t("voyageJournalPrompt")}
      </label>
      <textarea
        id="voyage-journal-body"
        className="voyage-journal-field"
        value={draft}
        maxLength={260}
        placeholder={t("voyageJournalPrompt")}
        onChange={(event) => {
          const next = event.target.value;
          setDraft(next);
          if (next === (entry?.body ?? "")) storage.sessionRemove(draftKey);
          else storage.sessionSet(draftKey, next);
          setSaved(false);
          setSaveFailed(false);
        }}
        onKeyDown={(event) => {
          if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
            event.preventDefault();
            void save();
          }
        }}
      />
      <div className="voyage-journal-actions">
        <span aria-live="polite">
          {saveFailed
            ? t("voyageJournalSaveFailed")
            : saved
              ? t("voyageJournalSaved")
              : `${draft.length} / 260`}
        </span>
        <div className="voyage-journal-action-buttons">
          {entry && (
            <button
              className="chip voyage-journal-delete"
              disabled={saving}
              onClick={() => void remove()}
            >
              {t("delete")}
            </button>
          )}
          <button
            className="primary-button"
            disabled={saving || (!draft.trim() && !entry)}
            onClick={() => void save()}
          >
            {t("voyageJournalSave")}
          </button>
        </div>
      </div>
      {draft !== (entry?.body ?? "") && draft.length > 0 && !saved && (
        <p className="field-meta">{t("voyageJournalDraft")}</p>
      )}

      <p className="section-label voyage-journal-recent-label">{t("voyageJournalRecent")}</p>
      {data.voyageLogs.length === 0 ? (
        <p className="empty-note">{t("voyageJournalEmpty")}</p>
      ) : (
        <>
          {archiveYears.length > 1 && (
            <div className="chip-row voyage-journal-years" aria-label={t("voyageJournalRecent")}>
              {archiveYears.map((year) => (
                <button
                  key={year}
                  className={`chip${archiveYear === year ? " selected" : ""}`}
                  onClick={() => setArchiveYear(year)}
                >
                  {year}
                </button>
              ))}
            </div>
          )}
          {archiveLogs.length === 0 ? (
            <p className="empty-note">{t("voyageJournalEmptyYear")}</p>
          ) : (
            <div className="voyage-journal-entries">
              {archiveLogs.map((log) => (
                <button
                  key={log.id}
                  className={`voyage-journal-entry${log.id === selectedId ? " selected" : ""}`}
                  onClick={() => selectDate(log.id)}
                >
                  <time>
                    {new Intl.DateTimeFormat(lang, {
                      month: "short",
                      day: "numeric",
                    }).format(log.date)}
                  </time>
                  <span>{log.body}</span>
                </button>
              ))}
            </div>
          )}
        </>
      )}
    </section>
  );
}

/// 年間海図。1年の海に12ヶ月の航路を描き、到達した島が浮かぶ。
function YearChart({ data }: { data: UserData }) {
  // タブ内の操作で再描画されても基準時刻オブジェクトを作り直さず、
  // 年一覧の集計を不要にやり直さない。
  const [now] = useState(() => new Date());
  const [year, setYear] = useState(now.getFullYear());

  const years = useMemo(() => {
    const set = new Set<number>([now.getFullYear()]);
    for (const d of data.days) set.add(d.date.getFullYear());
    return [...set].sort((a, b) => b - a);
  }, [data.days, now]);

  // 月ごとの学んだ日数(航路の点の明るさになる)
  const counts = Array.from({ length: 12 }, (_, m) =>
    data.days.filter((d) => d.date.getFullYear() === year && d.date.getMonth() === m).length,
  );
  const islands = data.destinations.filter(
    (d) => d.achievedAt && d.achievedAt.getFullYear() === year,
  );

  const px = (m: number) => 70 + (m * (880 - 140)) / 11;
  const py = (m: number) => 250 + Math.sin(m * 0.9) * 70;
  let route = `M ${px(0)} ${py(0)}`;
  for (let m = 1; m < 12; m++) {
    const cx = (px(m - 1) + px(m)) / 2;
    route += ` Q ${cx} ${py(m - 1)} ${px(m)} ${py(m)}`;
  }
  const currentMonth = year === now.getFullYear() ? now.getMonth() : 11;

  return (
    <div>
      {years.length > 1 && (
        <div className="chip-row" style={{ marginBottom: 16 }}>
          {years.map((y) => (
            <button
              key={y}
              className={`chip${y === year ? " selected" : ""}`}
              onClick={() => setYear(y)}
            >
              {y}
            </button>
          ))}
        </div>
      )}
      <div className="year-chart">
        <svg viewBox="0 0 880 480" aria-hidden="true">
          <circle cx="120" cy="60" r="3" fill="#EADEBD" opacity="0.3" />
          <circle cx="420" cy="40" r="4" fill="#EADEBD" opacity="0.35" />
          <circle cx="700" cy="70" r="3" fill="#EADEBD" opacity="0.3" />
          <circle cx="800" cy="120" r="22" fill="#EADEBD" opacity="0.85" />
          <text x="40" y="52" fill="#EADEBD" fontSize="24" fontWeight="500">
            {yearChartTitle(year)}
          </text>

          <path
            d={route}
            fill="none"
            stroke="#EADEBD"
            strokeOpacity="0.3"
            strokeWidth="2.5"
            strokeDasharray="2 9"
            strokeLinecap="round"
          />

          {counts.map((count, m) => {
            // その月に到達した島があれば、名前は出さず小さな灯りの印だけ点す
            // (名前・日付は下のReachedIslandsが読みやすい一覧として持つ — ここで
            //  フルサイズの島+文字を重ねると、細い年間航路の上で潰れて読めなくなる)。
            // マウスを載せた人には <title> で島の名前をそっと明かす。
            const landedNames = islands
              .filter((d) => d.achievedAt!.getMonth() === m)
              .map((d) => d.name);
            return (
              <g key={m}>
                <circle
                  cx={px(m)}
                  cy={py(m)}
                  r={count > 0 ? 9 : 5}
                  fill="#EADEBD"
                  opacity={count > 0 ? 0.35 + Math.min(0.65, count / 20) : 0.15}
                />
                {landedNames.length > 0 && (
                  <g>
                    <title>{landedNames.join(" / ")}</title>
                    <path
                      d={`M ${px(m) - 6} ${py(m) - 9} L ${px(m)} ${py(m) - 20} L ${px(m) + 6} ${py(m) - 9} Z`}
                      fill="#F5822A"
                    />
                  </g>
                )}
                <text
                  x={px(m)}
                  y={py(m) + 34}
                  fill="#EADEBD"
                  opacity="0.5"
                  fontSize="15"
                  textAnchor="middle"
                >
                  {m + 1}
                </text>
              </g>
            );
          })}

          {/* いまの位置の船 */}
          <g
            transform={`translate(${px(currentMonth) - 18}, ${py(currentMonth) - 44}) scale(0.14)`}
          >
            <BoatGroup {...boatProps()} />
          </g>
        </svg>
      </div>
    </div>
  );
}

/// 到達した島。目的地に着岸した記録が、ここに残り続ける。
/// 本人の記録なので、要らなくなった島は削除できる(確認あり)。
function ReachedIslands({ uid, data }: { uid: string; data: UserData }) {
  const reached = data.destinations
    .filter((d) => d.achievedAt)
    .sort((a, b) => (b.achievedAt?.getTime() ?? 0) - (a.achievedAt?.getTime() ?? 0));
  if (reached.length === 0) return null;
  const fmt = new Intl.DateTimeFormat(lang, { year: "numeric", month: "long", day: "numeric" });
  const remove = async (id: string) => {
    const ok = await askConfirm({
      title: t("deleteDestination"),
      message: t("deleteDestinationConfirm"),
      confirmLabel: t("delete"),
      danger: true,
    });
    if (ok) await deleteDestination(uid, id);
  };
  return (
    <div>
      <p className="section-label">{t("reachedIslands")}</p>
      <div className="rows">
        {reached.map((d) => (
          <div key={d.id} className="row">
            <span className="island-mark" aria-hidden="true" />
            <div className="row-main">
              <div className="row-title">{d.name}</div>
              <div className="row-sub">{d.achievedAt ? fmt.format(d.achievedAt) : ""}</div>
            </div>
            <button
              className="minus-button"
              onClick={() => void remove(d.id)}
              aria-label={t("delete")}
            >
              −
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}
