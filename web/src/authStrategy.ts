export function isEmbeddedWebViewUserAgent(userAgent: string): boolean {
  if (/FBAN|FBAV|Instagram|Line\/|MicroMessenger|TikTok/i.test(userAgent)) return true;
  if (/Twitter/i.test(userAgent)) return true;
  return /; wv\)/.test(userAgent);
}
