import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const headers = await readFile(new URL("../public/_headers", import.meta.url), "utf8");
const contentSecurityPolicy = headers
  .split("\n")
  .find((line) => line.trimStart().startsWith("Content-Security-Policy:"));

test("production CSP permits every external script required by Firebase Auth", () => {
  assert.ok(contentSecurityPolicy, "Content-Security-Policy header is missing");
  assert.match(contentSecurityPolicy, /script-src[^;]*https:\/\/apis\.google\.com(?:[ ;]|$)/);
});
