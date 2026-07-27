// Safari のプライベートブラウズや埋め込みブラウザでは、Storage へのアクセス自体が
// 例外になることがある。航海を止めず、保存できる環境では従来どおり記憶する。
function read(store: "localStorage" | "sessionStorage", key: string): string | null {
  try {
    return window[store].getItem(key);
  } catch {
    return null;
  }
}

function write(
  store: "localStorage" | "sessionStorage",
  key: string,
  value: string,
): boolean {
  try {
    window[store].setItem(key, value);
    return true;
  } catch {
    return false;
  }
}

function remove(store: "localStorage" | "sessionStorage", key: string): void {
  try {
    window[store].removeItem(key);
  } catch {
    // 保存領域が使えなくても、現在の画面操作は続けられる。
  }
}

export const storage = {
  get: (key: string) => read("localStorage", key),
  set: (key: string, value: string) => write("localStorage", key, value),
  remove: (key: string) => remove("localStorage", key),
  sessionGet: (key: string) => read("sessionStorage", key),
  sessionSet: (key: string, value: string) => write("sessionStorage", key, value),
  sessionRemove: (key: string) => remove("sessionStorage", key),
};
