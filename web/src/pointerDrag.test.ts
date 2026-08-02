import assert from "node:assert/strict";
import test from "node:test";
import { shouldCapturePointer } from "./pointerDrag.ts";

test("leaves touch gestures on the control background available for page scrolling", () => {
  assert.equal(shouldCapturePointer("touch", false), false);
});

test("captures touch only when the user starts from the visible drag handle", () => {
  assert.equal(shouldCapturePointer("touch", true), true);
});

test("keeps continuous dragging for mouse and pen input", () => {
  assert.equal(shouldCapturePointer("mouse", false), true);
  assert.equal(shouldCapturePointer("pen", false), true);
});
