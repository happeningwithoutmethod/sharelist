import { API_ORIGIN, WS_URL } from '../config';
import { decodeHtmlEntities } from '../lib/htmlEntities';
import type { Track } from '../protocol/types';

export function httpOriginFromWs(serverUrl: string): string {
  let value = serverUrl.trim().replace(/\/+$/, '');
  if (value.startsWith('wss://')) value = `https://${value.slice(6)}`;
  else if (value.startsWith('ws://')) value = `http://${value.slice(5)}`;
  else if (!/^https?:\/\//i.test(value)) value = `https://${value}`;
  return value.replace(/\/session$/i, '').replace(/\/+$/, '');
}

export async function checkRelayHealth(wsUrl = WS_URL): Promise<boolean> {
  const origin = httpOriginFromWs(wsUrl);
  try {
    const res = await fetch(`${origin}/health`, { cache: 'no-store' });
    return res.ok;
  } catch {
    return false;
  }
}

export async function resolveJoinCode(code: string): Promise<{
  joinCode: string;
  sessionId: string;
  serverUrl: string;
  sessionName?: string;
}> {
  const normalized = code.trim().toUpperCase();
  const res = await fetch(`${API_ORIGIN}/api/join/${encodeURIComponent(normalized)}`);
  if (res.status === 404) throw new Error(`No active session for code ${normalized}`);
  if (!res.ok) throw new Error(`Could not look up code (${res.status})`);
  return res.json();
}

export async function fetchHostJoinCode(input: {
  sessionId: string;
  sessionToken: string;
  serverUrl?: string;
}): Promise<string | null> {
  const origin = httpOriginFromWs(input.serverUrl || WS_URL);
  const url = new URL(`${origin}/api/host/join-code`);
  url.searchParams.set('sessionId', input.sessionId);
  url.searchParams.set('sessionToken', input.sessionToken);
  const res = await fetch(url);
  if (!res.ok) return null;
  const body = (await res.json()) as { joinCode?: string };
  const code = body.joinCode?.trim().toUpperCase();
  return code && /^[A-Z0-9]{6}$/.test(code) ? code : null;
}

export async function searchMusic(query: string, serverUrl?: string): Promise<Track[]> {
  const origin = httpOriginFromWs(serverUrl || WS_URL);
  const url = new URL(`${origin}/api/music/search`);
  url.searchParams.set('q', query);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Search failed (${res.status})`);
  const body = (await res.json()) as { tracks?: Track[] };
  return (body.tracks ?? []).map((track) => ({
    ...track,
    title: decodeHtmlEntities(track.title),
    artist: decodeHtmlEntities(track.artist),
  }));
}

export function isJoinCode(raw: string): boolean {
  return /^[A-Z0-9]{6}$/.test(raw.trim().toUpperCase());
}

export function normalizeServerUrl(raw: string): string {
  let value = raw.trim().replace(/\/+$/, '');
  if (value.startsWith('https://')) value = `wss://${value.slice(8)}`;
  else if (value.startsWith('http://')) value = `ws://${value.slice(7)}`;
  return value;
}
