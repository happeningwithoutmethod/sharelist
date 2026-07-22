export const WS_URL =
  (import.meta.env.VITE_WS_URL as string | undefined)?.replace(/\/+$/, '') ||
  'wss://sharelist.servehttp.com';

export const API_ORIGIN =
  (import.meta.env.VITE_API_ORIGIN as string | undefined)?.replace(/\/+$/, '') ||
  'https://sharelist.servehttp.com';

export const GOOGLE_CLIENT_ID =
  (import.meta.env.VITE_GOOGLE_CLIENT_ID as string | undefined)?.trim() || '';

export const APP_BASENAME = '/web';
