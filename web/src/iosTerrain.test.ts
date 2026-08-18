import assert from "node:assert/strict";
import test from "node:test";
import { buildIOSTerrain, type IOSTerrainStroke } from "./three/iosTerrain.ts";

const strokes: IOSTerrainStroke[] = [
  {
    id: "4D45C2F0-BCB8-4DF4-8980-1311AE7A47AF",
    tool: "raise",
    radius: 1.3,
    strength: 1.85,
    shape: "mountain",
    material: "sand",
    points: [{ x: -0.55, y: 0.98, z: -1.87 }],
  },
  {
    id: "CC08FDF9-AFE3-4B34-BAE9-59B27CC14586",
    tool: "raise",
    radius: 0.78,
    strength: 1.25,
    shape: "ridge",
    material: "sand",
    points: [{ x: -1.7, y: 0.82, z: 0.95 }],
  },
];

test("rebuilds iOS terrain strokes as one sampled surface", () => {
  const terrain = buildIOSTerrain(strokes);
  assert.ok(terrain);
  assert.ok((terrain.geometry.getIndex()?.count ?? 0) > 0);
  assert.ok((terrain.heightField.heightAt(-0.55, -1.87) ?? 0) > 2.5);
  assert.equal(terrain.heightField.heightAt(100, 100), undefined);
  assert.ok(terrain.heightField.normalAt(-0.55, -1.87)?.y);
  terrain.geometry.dispose();
});

test("uses deterministic iOS terrain noise", () => {
  const first = buildIOSTerrain(strokes);
  const second = buildIOSTerrain(strokes);
  assert.ok(first && second);
  assert.deepEqual(
    Array.from(first.geometry.getAttribute("position").array),
    Array.from(second.geometry.getAttribute("position").array),
  );
  first.geometry.dispose();
  second.geometry.dispose();
});
