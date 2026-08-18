import assert from "node:assert/strict";
import test from "node:test";
import { isEmbeddedWebViewUserAgent } from "./authStrategy.ts";

const iphoneSafari =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 Version/18.6 Mobile/15E148 Safari/604.1";
test("embedded browsers are recognized narrowly", () => {
  assert.equal(isEmbeddedWebViewUserAgent("Mozilla/5.0 Instagram 380.0"), true);
  assert.equal(isEmbeddedWebViewUserAgent("Mozilla/5.0 Line/15.0"), true);
  assert.equal(isEmbeddedWebViewUserAgent("Mozilla/5.0; wv)"), true);
  assert.equal(isEmbeddedWebViewUserAgent(iphoneSafari), false);
});
