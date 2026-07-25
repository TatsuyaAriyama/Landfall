/// WebGLが使えるか(一度だけ判定して覚える)。
/// 使えない環境では3Dの世界を出さず、2Dのままにする。
let cache: boolean | null = null;

export function canUseWebGL(): boolean {
  if (cache !== null) return cache;
  try {
    const c = document.createElement("canvas");
    cache = Boolean(
      window.WebGLRenderingContext && (c.getContext("webgl2") || c.getContext("webgl")),
    );
  } catch {
    cache = false;
  }
  return cache;
}
