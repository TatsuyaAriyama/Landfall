import * as THREE from "three";

export type IOSPoint = { x: number; y: number; z: number };

export type IOSTerrainStroke = {
  id: string;
  tool: "raise" | "lower" | "smooth";
  radius: number;
  strength: number;
  shape?: "hill" | "mountain" | "plateau" | "ridge";
  material?: "grass" | "earth" | "sand" | "rock" | "snow";
  points: IOSPoint[];
};

type TerrainMaterial = NonNullable<IOSTerrainStroke["material"]>;
type RGB = [number, number, number];

const MATERIAL_COLORS: Record<TerrainMaterial, RGB> = {
  grass: hexRGB(0x62a164),
  earth: hexRGB(0x9a6847),
  sand: hexRGB(0xe5c980),
  rock: hexRGB(0x7d8074),
  snow: hexRGB(0xe2e9df),
};

function clamp(value: number, minimum: number, maximum: number) {
  return Math.min(Math.max(value, minimum), maximum);
}

function hexRGB(value: number): RGB {
  return [((value >> 16) & 255) / 255, ((value >> 8) & 255) / 255, (value & 255) / 255];
}

function blend(left: RGB, right: RGB, amount: number): RGB {
  const t = clamp(amount, 0, 1);
  return [
    left[0] + (right[0] - left[0]) * t,
    left[1] + (right[1] - left[1]) * t,
    left[2] + (right[2] - left[2]) * t,
  ];
}

function uuidSeed(id: string) {
  let value = 2_166_136_261;
  for (const byte of new TextEncoder().encode(id.toUpperCase())) {
    value = Math.imul((value ^ byte) >>> 0, 16_777_619) >>> 0;
  }
  return (value % 10_000) * 0.001;
}

function terrainDetail(x: number, z: number, seed: number) {
  const broad = Math.sin(x * 1.37 + seed * 0.73) * Math.cos(z * 1.11 - seed * 0.41);
  const fine =
    Math.sin((x + z) * 3.17 + seed * 1.91) * Math.cos((x - z) * 2.43 - seed * 0.83);
  return broad * 0.68 + fine * 0.32;
}

function terrainSurfaceColor(
  material: TerrainMaterial,
  elevation: number,
  steepness: number,
  detail: number,
): RGB {
  const rock = hexRGB(0x74796f);
  const snow = hexRGB(0xdfe7df);
  let color: RGB;
  switch (material) {
    case "grass":
      color = blend(
        MATERIAL_COLORS.grass,
        hexRGB(0x426f4a),
        clamp((steepness - 0.12) / 0.3, 0, 0.72),
      );
      break;
    case "earth":
      color = blend(
        MATERIAL_COLORS.earth,
        hexRGB(0x6e4937),
        clamp((steepness - 0.14) / 0.34, 0, 0.66),
      );
      break;
    case "sand":
      color = blend(
        MATERIAL_COLORS.sand,
        hexRGB(0xbfae83),
        clamp((steepness - 0.16) / 0.34, 0, 0.58),
      );
      break;
    case "rock":
      color = blend(MATERIAL_COLORS.rock, hexRGB(0xa4a696), clamp(elevation / 7, 0, 0.48));
      break;
    case "snow":
      color = blend(
        MATERIAL_COLORS.snow,
        rock,
        clamp((steepness - 0.18) / 0.34, 0, 0.72),
      );
      break;
  }

  if (material === "grass" || material === "earth") {
    color = blend(color, rock, clamp((steepness - 0.27) / 0.25, 0, 0.7));
    const snowLine = 5.4 + detail * 0.55;
    const snowAmount =
      clamp((elevation - snowLine) / 2.4, 0, 0.82) * clamp((0.56 - steepness) / 0.34, 0, 1);
    color = blend(color, snow, snowAmount);
  }
  return color;
}

function resampledPoints(stroke: IOSTerrainStroke) {
  if (stroke.points.length <= 1) return stroke.points;
  const spacing = Math.max(stroke.radius * 0.18, 0.055);
  const result: IOSPoint[] = [stroke.points[0]];
  for (let index = 1; index < stroke.points.length; index += 1) {
    const start = stroke.points[index - 1];
    const end = stroke.points[index];
    const dx = end.x - start.x;
    const dy = end.y - start.y;
    const dz = end.z - start.z;
    const distance = Math.hypot(dx, dz);
    const steps = Math.max(Math.ceil(distance / spacing), 1);
    for (let step = 1; step <= steps; step += 1) {
      const progress = step / steps;
      result.push({
        x: start.x + dx * progress,
        y: start.y + dy * progress,
        z: start.z + dz * progress,
      });
    }
  }
  return result;
}

export class IOSTerrainHeightField {
  readonly minimumX: number;
  readonly minimumZ: number;
  readonly stepX: number;
  readonly stepZ: number;
  readonly columns: number;
  readonly rows: number;
  readonly heights: Float32Array;
  readonly coverage: Float32Array;

  constructor(
    minimumX: number,
    minimumZ: number,
    stepX: number,
    stepZ: number,
    columns: number,
    rows: number,
    heights: Float32Array,
    coverage: Float32Array,
  ) {
    this.minimumX = minimumX;
    this.minimumZ = minimumZ;
    this.stepX = stepX;
    this.stepZ = stepZ;
    this.columns = columns;
    this.rows = rows;
    this.heights = heights;
    this.coverage = coverage;
  }

  heightAt(x: number, z: number): number | undefined {
    const gridX = (x - this.minimumX) / Math.max(this.stepX, 0.0001);
    const gridZ = (z - this.minimumZ) / Math.max(this.stepZ, 0.0001);
    if (gridX < 0 || gridZ < 0 || gridX > this.columns - 1 || gridZ > this.rows - 1) {
      return undefined;
    }
    const left = clamp(Math.floor(gridX), 0, this.columns - 1);
    const top = clamp(Math.floor(gridZ), 0, this.rows - 1);
    const right = Math.min(left + 1, this.columns - 1);
    const bottom = Math.min(top + 1, this.rows - 1);
    const fractionX = gridX - left;
    const fractionZ = gridZ - top;
    const interpolate = (values: Float32Array) => {
      const topValue =
        values[top * this.columns + left] +
        (values[top * this.columns + right] - values[top * this.columns + left]) * fractionX;
      const bottomValue =
        values[bottom * this.columns + left] +
        (values[bottom * this.columns + right] - values[bottom * this.columns + left]) * fractionX;
      return topValue + (bottomValue - topValue) * fractionZ;
    };
    if (interpolate(this.coverage) <= 0.025) return undefined;
    return interpolate(this.heights);
  }

  normalAt(x: number, z: number): THREE.Vector3 | undefined {
    const center = this.heightAt(x, z);
    if (center === undefined) return undefined;
    const sampleX = Math.max(this.stepX, 0.025);
    const sampleZ = Math.max(this.stepZ, 0.025);
    const left = this.heightAt(x - sampleX, z) ?? center;
    const right = this.heightAt(x + sampleX, z) ?? center;
    const near = this.heightAt(x, z - sampleZ) ?? center;
    const far = this.heightAt(x, z + sampleZ) ?? center;
    return new THREE.Vector3(
      -(right - left) / Math.max(sampleX * 2, 0.0001),
      1,
      -(far - near) / Math.max(sampleZ * 2, 0.0001),
    ).normalize();
  }
}

export type IOSTerrainMeshData = {
  geometry: THREE.BufferGeometry;
  heightField: IOSTerrainHeightField;
};

export function buildIOSTerrain(strokes: IOSTerrainStroke[]): IOSTerrainMeshData | undefined {
  const validStrokes = strokes.filter((stroke) => stroke.points.length > 0 && stroke.radius > 0.02);
  if (validStrokes.length === 0) return undefined;
  const renderPoints = new Map(validStrokes.map((stroke) => [stroke.id, resampledPoints(stroke)]));
  const allPoints = validStrokes.flatMap((stroke) => renderPoints.get(stroke.id) ?? stroke.points);
  if (allPoints.length === 0) return undefined;

  const largestRadius = Math.max(...validStrokes.map((stroke) => stroke.radius));
  const padding = largestRadius * 1.06;
  const minimumX = Math.min(...allPoints.map((point) => point.x)) - padding;
  const maximumX = Math.max(...allPoints.map((point) => point.x)) + padding;
  const minimumZ = Math.min(...allPoints.map((point) => point.z)) - padding;
  const maximumZ = Math.max(...allPoints.map((point) => point.z)) + padding;
  const width = Math.max(maximumX - minimumX, 0.2);
  const depth = Math.max(maximumZ - minimumZ, 0.2);
  const smallestRadius = Math.min(...validStrokes.map((stroke) => stroke.radius));
  const preferredStep = Math.min(Math.max(smallestRadius / 13, 0.045), 0.14);
  const columns = clamp(Math.ceil(width / preferredStep) + 1, 7, 193);
  const rows = clamp(Math.ceil(depth / preferredStep) + 1, 7, 193);
  const stepX = width / (columns - 1);
  const stepZ = depth / (rows - 1);
  const vertexCount = columns * rows;
  const averageBaseY = allPoints.reduce((total, point) => total + point.y, 0) / allPoints.length;
  const baseHeights = new Float32Array(vertexCount).fill(averageBaseY);
  const nearestBaseDistances = new Float64Array(vertexCount).fill(Number.MAX_VALUE);

  const affectedRange = (coordinate: number, minimum: number, step: number, radius: number, count: number) => [
    Math.max(0, Math.floor((coordinate - radius - minimum) / step)),
    Math.min(count - 1, Math.ceil((coordinate + radius - minimum) / step)),
  ] as const;

  for (const stroke of validStrokes) {
    const reach = stroke.radius * 1.5;
    for (const point of renderPoints.get(stroke.id) ?? stroke.points) {
      const [columnStart, columnEnd] = affectedRange(point.x, minimumX, stepX, reach, columns);
      const [rowStart, rowEnd] = affectedRange(point.z, minimumZ, stepZ, reach, rows);
      for (let row = rowStart; row <= rowEnd; row += 1) {
        const z = minimumZ + row * stepZ;
        for (let column = columnStart; column <= columnEnd; column += 1) {
          const x = minimumX + column * stepX;
          const distanceSquared = (x - point.x) ** 2 + (z - point.z) ** 2;
          const index = row * columns + column;
          if (distanceSquared < nearestBaseDistances[index]) {
            nearestBaseDistances[index] = distanceSquared;
            baseHeights[index] = point.y;
          }
        }
      }
    }
  }

  const heights = new Float32Array(baseHeights);
  const raisedRelief = new Float32Array(vertexCount);
  const surfaceMaterials = new Array<TerrainMaterial>(vertexCount).fill("grass");
  const weatheringMask = new Float32Array(vertexCount);

  for (const stroke of validStrokes) {
    const influence = new Float32Array(vertexCount);
    const radius = Math.max(stroke.radius, 0.03);
    for (const point of renderPoints.get(stroke.id) ?? stroke.points) {
      const [columnStart, columnEnd] = affectedRange(point.x, minimumX, stepX, radius, columns);
      const [rowStart, rowEnd] = affectedRange(point.z, minimumZ, stepZ, radius, rows);
      for (let row = rowStart; row <= rowEnd; row += 1) {
        const z = minimumZ + row * stepZ;
        for (let column = columnStart; column <= columnEnd; column += 1) {
          const x = minimumX + column * stepX;
          const normalizedDistance = Math.hypot(x - point.x, z - point.z) / radius;
          if (normalizedDistance >= 1) continue;
          const remaining = 1 - normalizedDistance;
          const smoothFalloff = remaining * remaining * (3 - 2 * remaining);
          let value: number;
          switch (stroke.shape ?? "hill") {
            case "mountain":
              value = remaining ** 1.32;
              break;
            case "plateau": {
              if (normalizedDistance <= 0.45) value = 1;
              else {
                const edge = Math.max(0, (1 - normalizedDistance) / 0.55);
                value = edge * edge * (3 - 2 * edge);
              }
              break;
            }
            case "ridge":
              value = smoothFalloff ** 0.72;
              break;
            default:
              value = smoothFalloff;
          }
          const index = row * columns + column;
          influence[index] = Math.max(influence[index], value);
        }
      }
    }

    const shape = stroke.shape ?? "hill";
    const seed = uuidSeed(stroke.id);
    if (stroke.tool === "raise") {
      for (let index = 0; index < vertexCount; index += 1) {
        if (influence[index] <= 0) continue;
        const row = Math.floor(index / columns);
        const column = index % columns;
        const detail = terrainDetail(minimumX + column * stepX, minimumZ + row * stepZ, seed);
        let delta = stroke.strength * influence[index];
        switch (shape) {
          case "hill":
            delta *= 1 + detail * 0.035 * Math.min(influence[index] * 2, 1);
            break;
          case "mountain":
            delta *= 1 + detail * 0.19 * influence[index] ** 0.42;
            weatheringMask[index] = Math.max(weatheringMask[index], influence[index]);
            break;
          case "plateau": {
            const terraceStep = Math.max(stroke.strength / 4.5, 0.08);
            const terraced = Math.floor(delta / terraceStep + 0.2) * terraceStep;
            delta = delta * 0.18 + terraced * 0.82;
            break;
          }
          case "ridge":
            delta *= 1 + detail * 0.12 * Math.min(influence[index] * 1.6, 1);
            weatheringMask[index] = Math.max(weatheringMask[index], influence[index] * 0.78);
            break;
        }
        const previousHeight = heights[index];
        heights[index] = Math.min(baseHeights[index] + 24, heights[index] + Math.max(delta, 0));
        raisedRelief[index] += Math.max(heights[index] - previousHeight, 0);
        if (influence[index] > 0.025) surfaceMaterials[index] = stroke.material ?? "grass";
      }
    } else if (stroke.tool === "lower") {
      for (let index = 0; index < vertexCount; index += 1) {
        if (influence[index] <= 0) continue;
        const row = Math.floor(index / columns);
        const column = index % columns;
        const detail = terrainDetail(minimumX + column * stepX, minimumZ + row * stepZ, seed);
        if (raisedRelief[index] > 0.002) {
          const delta = stroke.strength * influence[index] * (1 + detail * 0.08);
          const removed = Math.min(Math.max(delta, 0), raisedRelief[index]);
          heights[index] = Math.max(baseHeights[index], heights[index] - removed);
          raisedRelief[index] = Math.max(raisedRelief[index] - removed, 0);
        } else {
          const shoulder = Math.max(0, 1 - Math.abs(influence[index] - 0.34) / 0.24);
          const bankHeight = stroke.strength * 0.3 * shoulder * (1 + detail * 0.07);
          heights[index] = Math.min(baseHeights[index] + 24, heights[index] + Math.max(bankHeight, 0));
          if (shoulder > 0.04) surfaceMaterials[index] = stroke.material ?? "earth";
        }
      }
    } else {
      for (let pass = 0; pass < 2; pass += 1) {
        const source = new Float32Array(heights);
        for (let row = 1; row < rows - 1; row += 1) {
          for (let column = 1; column < columns - 1; column += 1) {
            const index = row * columns + column;
            if (influence[index] <= 0) continue;
            let total = 0;
            for (let neighborRow = row - 1; neighborRow <= row + 1; neighborRow += 1) {
              for (let neighborColumn = column - 1; neighborColumn <= column + 1; neighborColumn += 1) {
                total += source[neighborRow * columns + neighborColumn];
              }
            }
            const average = total / 9;
            const amount = Math.min(0.92, stroke.strength * 1.8) * influence[index];
            heights[index] = Math.max(
              baseHeights[index],
              source[index] + (average - source[index]) * amount,
            );
          }
        }
      }
    }
  }

  for (let pass = 0; pass < 2; pass += 1) {
    const source = new Float32Array(heights);
    for (let row = 1; row < rows - 1; row += 1) {
      for (let column = 1; column < columns - 1; column += 1) {
        const index = row * columns + column;
        const mask = weatheringMask[index];
        if (mask <= 0.02) continue;
        const neighborAverage =
          (source[index - 1] + source[index + 1] + source[index - columns] + source[index + columns]) / 4;
        const difference = neighborAverage - source[index];
        const excessSlope = Math.max(Math.abs(difference) - 0.11, 0);
        const amount = Math.min(excessSlope * 0.16 * mask, 0.075);
        heights[index] = Math.max(
          baseHeights[index],
          source[index] + (difference < 0 ? -amount : amount),
        );
      }
    }
  }

  const positions = new Float32Array(vertexCount * 3);
  const normals = new Float32Array(vertexCount * 3);
  const colors = new Float32Array(vertexCount * 3);
  for (let row = 0; row < rows; row += 1) {
    for (let column = 0; column < columns; column += 1) {
      const index = row * columns + column;
      const left = heights[row * columns + Math.max(column - 1, 0)];
      const right = heights[row * columns + Math.min(column + 1, columns - 1)];
      const near = heights[Math.max(row - 1, 0) * columns + column];
      const far = heights[Math.min(row + 1, rows - 1) * columns + column];
      const normal = new THREE.Vector3(
        -(right - left) / Math.max(stepX * 2, 0.0001),
        1,
        -(far - near) / Math.max(stepZ * 2, 0.0001),
      ).normalize();
      const x = minimumX + column * stepX;
      const z = minimumZ + row * stepZ;
      const detail = terrainDetail(x, z, 7.31);
      const color = terrainSurfaceColor(
        surfaceMaterials[index],
        heights[index] - baseHeights[index],
        1 - normal.y,
        detail,
      );
      const tone = 0.965 + detail * 0.045;
      positions.set([x, heights[index] + 0.004, z], index * 3);
      normals.set([normal.x, normal.y, normal.z], index * 3);
      colors.set(color.map((component) => clamp(component * tone, 0, 1)), index * 3);
    }
  }

  const indices: number[] = [];
  for (let row = 0; row < rows - 1; row += 1) {
    for (let column = 0; column < columns - 1; column += 1) {
      const nearLeft = row * columns + column;
      const nearRight = nearLeft + 1;
      const farLeft = (row + 1) * columns + column;
      const farRight = farLeft + 1;
      if (
        [nearLeft, nearRight, farLeft, farRight].every(
          (index) => heights[index] - baseHeights[index] <= 0.001,
        )
      ) {
        continue;
      }
      indices.push(nearLeft, farLeft, nearRight, nearRight, farLeft, farRight);
    }
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  geometry.setAttribute("normal", new THREE.BufferAttribute(normals, 3));
  geometry.setAttribute("color", new THREE.BufferAttribute(colors, 3));
  geometry.setIndex(indices);
  geometry.computeBoundingBox();
  geometry.computeBoundingSphere();
  const coverage = new Float32Array(vertexCount);
  for (let index = 0; index < vertexCount; index += 1) {
    coverage[index] = clamp(Math.abs(heights[index] - baseHeights[index]) / 0.018, 0, 1);
  }
  return {
    geometry,
    heightField: new IOSTerrainHeightField(
      minimumX,
      minimumZ,
      stepX,
      stepZ,
      columns,
      rows,
      heights,
      coverage,
    ),
  };
}

export function buildIOSPaintCap(
  id: string,
  point: IOSPoint,
  width: number,
  heightField: IOSTerrainHeightField | undefined,
) {
  const segments = 12;
  const radius = Math.max(width * 0.5, 0.025);
  const surfaceOffset = 0.0165;
  const centerY = heightField?.heightAt(point.x, point.z) ?? point.y;
  const normal = heightField?.normalAt(point.x, point.z) ?? new THREE.Vector3(0, 1, 0);
  const positions: number[] = [point.x, centerY + surfaceOffset, point.z];
  const normals: number[] = [normal.x, normal.y, normal.z];
  const colors: number[] = [1.025, 1.025, 1.025];
  const indices: number[] = [];
  const seed = uuidSeed(id);
  for (let segment = 0; segment < segments; segment += 1) {
    const angle = (segment / segments) * Math.PI * 2;
    const wobble = 1 + Math.sin(segment * 2.31 + seed) * 0.048;
    const dx = Math.cos(angle) * radius * wobble;
    const dz = Math.sin(angle) * radius * wobble;
    const safeNormalY = Math.max(Math.abs(normal.y), 0.18);
    const dy = -(normal.x * dx + normal.z * dz) / safeNormalY;
    const x = point.x + dx;
    const z = point.z + dz;
    const y = heightField?.heightAt(x, z) ?? point.y + dy;
    positions.push(x, y + surfaceOffset, z);
    normals.push(normal.x, normal.y, normal.z);
    const tone = 0.94 + Math.sin(segment * 1.41 + seed * 0.7) * 0.035;
    colors.push(tone, tone, tone);
  }
  for (let segment = 0; segment < segments; segment += 1) {
    const current = segment + 1;
    const next = ((segment + 1) % segments) + 1;
    indices.push(0, next, current);
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geometry.setAttribute("normal", new THREE.Float32BufferAttribute(normals, 3));
  geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
  geometry.setIndex(indices);
  geometry.computeBoundingBox();
  geometry.computeBoundingSphere();
  return geometry;
}
