type RuntimeEnv = {
  VITE_WS_URL?: string;
  VITE_API_ORIGIN?: string;
  VITE_GOOGLE_CLIENT_ID?: string;
};

declare global {
  interface Window {
    __SHARE_LIST_ENV__?: RuntimeEnv;
  }
}

function readEnv(key: keyof RuntimeEnv): string {
  const fromRuntime = window.__SHARE_LIST_ENV__?.[key]?.trim();
  if (fromRuntime) return fromRuntime;
  const fromVite = (import.meta.env[key] as string | undefined)?.trim();
  return fromVite ?? '';
}

export const WS_URL =
  readEnv('VITE_WS_URL').replace(/\/+$/, '') || 'wss://sharelist.servehttp.com';

export const API_ORIGIN =
  readEnv('VITE_API_ORIGIN').replace(/\/+$/, '') ||
  'https://sharelist.servehttp.com';

export const GOOGLE_CLIENT_ID = readEnv('VITE_GOOGLE_CLIENT_ID');

export const APP_BASENAME = '/web';
