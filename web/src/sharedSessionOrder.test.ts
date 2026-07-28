import assert from "node:assert/strict";
import test from "node:test";
import { newestSharedSessionsFirst } from "./sharedSessionOrder.ts";

test("orders shared sessions by newest timestamp without mutating the source", () => {
  const source = [
    { id: "old", day: 28, date: new Date("2026-07-28T08:00:00+09:00") },
    { id: "new", day: 28, date: new Date("2026-07-28T14:00:00+09:00") },
    { id: "middle", day: 28, date: new Date("2026-07-28T10:00:00+09:00") },
  ];

  assert.deepEqual(
    newestSharedSessionsFirst(source).map((session) => session.id),
    ["new", "middle", "old"],
  );
  assert.deepEqual(
    source.map((session) => session.id),
    ["old", "new", "middle"],
  );
});

test("keeps dated records first and falls back to newest day for legacy records", () => {
  const sessions = [
    { id: "legacy-old-day", day: 2 },
    { id: "dated", day: 3, date: new Date("2026-07-03T09:00:00+09:00") },
    { id: "legacy-new-day", day: 5 },
    { id: "legacy-same-day", day: 3 },
  ];

  assert.deepEqual(
    newestSharedSessionsFirst(sessions).map((session) => session.id),
    ["legacy-new-day", "dated", "legacy-same-day", "legacy-old-day"],
  );
});
