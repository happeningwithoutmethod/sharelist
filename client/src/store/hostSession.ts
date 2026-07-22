import { create } from 'zustand';
import { v4 as uuid } from 'uuid';
import { fetchHostJoinCode } from '../api/relay';
import { WS_URL } from '../config';
import {
  createEmptyHostState,
  type ConnectorInfo,
  type HostSettings,
  type HostState,
  type Track,
} from '../protocol/types';
import { SessionClient } from '../ws/sessionClient';
import type { AuthUser } from './auth';

const HOST_SESSION_KEY = 'sharelist.hostSession';

export interface StoredHostSession {
  sessionId: string;
  sessionToken: string;
  serverUrl: string;
  hostGoogleSub: string;
  joinCode?: string;
}

function loadStored(): StoredHostSession | null {
  try {
    const raw = localStorage.getItem(HOST_SESSION_KEY);
    return raw ? (JSON.parse(raw) as StoredHostSession) : null;
  } catch {
    return null;
  }
}

function saveStored(session: StoredHostSession | null): void {
  if (!session) localStorage.removeItem(HOST_SESSION_KEY);
  else localStorage.setItem(HOST_SESSION_KEY, JSON.stringify(session));
}

interface HostSessionStore {
  connected: boolean;
  busy: boolean;
  error: string | null;
  sessionId: string | null;
  sessionToken: string | null;
  joinCode: string | null;
  serverUrl: string;
  hostGoogleSub: string | null;
  state: HostState;
  pendingConnections: ConnectorInfo[];
  storedSession: StoredHostSession | null;
  client: SessionClient | null;

  startSession: (input: {
    user: AuthUser;
    sessionName?: string;
    serverUrl?: string;
  }) => Promise<void>;
  reconnectSession: (user: AuthUser) => Promise<void>;
  endSession: () => Promise<void>;
  broadcastState: () => void;
  updatePlayback: (patch: Partial<Pick<HostState, 'nowPlayingIndex' | 'isPlaying' | 'positionMs' | 'durationMs'>>) => void;
  setPlaylist: (playlist: Track[]) => void;
  addTrack: (track: Track) => void;
  removeTrack: (trackId: string) => void;
  playIndex: (index: number) => void;
  updateSettings: (patch: Partial<HostSettings>) => void;
  approveRequest: (requestId: string, placement: 'top' | 'bottom') => void;
  rejectRequest: (requestId: string) => void;
  approveConnector: (deviceId: string) => void;
  rejectConnector: (deviceId: string) => void;
  refreshJoinCode: () => Promise<void>;
  clearError: () => void;
}

let lastBroadcastAt = 0;

function youtubeIdFromTrack(track: Track): string {
  try {
    const url = new URL(track.sourceUrl);
    if (url.hostname.includes('youtu.be')) return url.pathname.slice(1);
    return url.searchParams.get('v') || track.id;
  } catch {
    return track.id;
  }
}

export { youtubeIdFromTrack };

export const useHostStore = create<HostSessionStore>((set, get) => ({
  connected: false,
  busy: false,
  error: null,
  sessionId: null,
  sessionToken: null,
  joinCode: null,
  serverUrl: WS_URL,
  hostGoogleSub: null,
  state: createEmptyHostState(),
  pendingConnections: [],
  storedSession: loadStored(),
  client: null,

  clearError: () => set({ error: null }),

  startSession: async ({ user, sessionName, serverUrl }) => {
    const resolvedUrl = (serverUrl || WS_URL).replace(/\/+$/, '');
    set({
      busy: true,
      error: null,
      connected: false,
      sessionId: null,
      sessionToken: null,
      joinCode: null,
      hostGoogleSub: user.id,
      serverUrl: resolvedUrl,
      state: createEmptyHostState(sessionName || 'Share List Session'),
      pendingConnections: [],
    });

    const client = new SessionClient(resolvedUrl);
    client.addHandler((message) => handleHostMessage(message, set, get));
    client.setDisconnectListener(() => {
      const current = get();
      if (current.sessionId) set({ connected: false, error: 'Connection lost' });
    });

    try {
      await client.connect();
      set({ client });
      client.send({
        type: 'host.start',
        payload: {
          hostGoogleSub: user.id,
          sessionName: sessionName || 'Share List Session',
          countryCode: 'unknown',
        },
      });
      await waitUntil(() => get().connected, 10_000);
      get().broadcastState();
    } catch (error) {
      await client.disconnect();
      set({
        client: null,
        busy: false,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    } finally {
      set({ busy: false });
    }
  },

  reconnectSession: async (user) => {
    const stored = get().storedSession;
    if (!stored) throw new Error('No stored session');
    if (stored.hostGoogleSub !== user.id) {
      throw new Error('Google account does not match session host');
    }

    set({
      busy: true,
      error: null,
      hostGoogleSub: user.id,
      serverUrl: stored.serverUrl,
      sessionId: stored.sessionId,
      sessionToken: stored.sessionToken,
      joinCode: stored.joinCode ?? null,
    });

    const client = new SessionClient(stored.serverUrl);
    client.addHandler((message) => handleHostMessage(message, set, get));
    client.setDisconnectListener(() => {
      if (get().sessionId) set({ connected: false, error: 'Connection lost' });
    });

    try {
      await client.connect();
      set({ client });
      client.send({
        type: 'host.reconnect',
        payload: {
          sessionId: stored.sessionId,
          sessionToken: stored.sessionToken,
          hostGoogleSub: user.id,
          countryCode: 'unknown',
          state: get().state,
        },
      });
      await waitUntil(() => get().connected, 10_000);
      get().broadcastState();
    } catch (error) {
      await client.disconnect();
      set({
        client: null,
        busy: false,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    } finally {
      set({ busy: false });
    }
  },

  endSession: async () => {
    const { client, sessionId } = get();
    if (client && sessionId) {
      client.send({ type: 'host.end', sessionId, payload: {} });
    }
    await client?.disconnect();
    saveStored(null);
    set({
      connected: false,
      client: null,
      sessionId: null,
      sessionToken: null,
      joinCode: null,
      storedSession: null,
      pendingConnections: [],
      state: createEmptyHostState(),
    });
  },

  broadcastState: () => {
    const { client, sessionId, state } = get();
    if (!client || !sessionId) return;
    client.send({ type: 'host.state', sessionId, payload: state });
    lastBroadcastAt = Date.now();
  },

  updatePlayback: (patch) => {
    const next = { ...get().state, ...patch };
    set({ state: next });
    const significant =
      patch.nowPlayingIndex != null ||
      patch.isPlaying != null ||
      patch.durationMs != null;
    const now = Date.now();
    if (!significant && now - lastBroadcastAt < 900) return;
    get().broadcastState();
  },

  setPlaylist: (playlist) => {
    const state = get().state;
    let nowPlayingIndex = state.nowPlayingIndex;
    if (nowPlayingIndex >= playlist.length) nowPlayingIndex = playlist.length - 1;
    set({ state: { ...state, playlist, nowPlayingIndex } });
    get().broadcastState();
  },

  addTrack: (track) => {
    const state = get().state;
    if (state.playlist.some((t) => t.id === track.id)) return;
    const playlist = [...state.playlist, track];
    const nowPlayingIndex =
      state.nowPlayingIndex < 0 && playlist.length === 1 ? 0 : state.nowPlayingIndex;
    set({
      state: {
        ...state,
        playlist,
        nowPlayingIndex,
        isPlaying: nowPlayingIndex === 0 && state.nowPlayingIndex < 0 ? true : state.isPlaying,
      },
    });
    get().broadcastState();
  },

  removeTrack: (trackId) => {
    const state = get().state;
    const index = state.playlist.findIndex((t) => t.id === trackId);
    if (index < 0) return;
    const playlist = state.playlist.filter((t) => t.id !== trackId);
    let nowPlayingIndex = state.nowPlayingIndex;
    if (index === state.nowPlayingIndex) {
      nowPlayingIndex = playlist.length === 0 ? -1 : Math.min(index, playlist.length - 1);
    } else if (index < state.nowPlayingIndex) {
      nowPlayingIndex -= 1;
    }
    const voteScores = { ...state.voteScores };
    delete voteScores[trackId];
    set({ state: { ...state, playlist, nowPlayingIndex, voteScores } });
    get().broadcastState();
  },

  playIndex: (index) => {
    const state = get().state;
    if (index < 0 || index >= state.playlist.length) return;
    set({
      state: {
        ...state,
        nowPlayingIndex: index,
        isPlaying: true,
        positionMs: 0,
      },
    });
    get().broadcastState();
  },

  updateSettings: (patch) => {
    const state = get().state;
    set({ state: { ...state, settings: { ...state.settings, ...patch } } });
    get().broadcastState();
  },

  approveRequest: (requestId, placement) => {
    const state = get().state;
    const request = state.pendingRequests.find((r) => r.id === requestId);
    if (!request) return;
    const pendingRequests = state.pendingRequests.filter((r) => r.id !== requestId);
    let playlist = [...state.playlist];
    if (!playlist.some((t) => t.id === request.track.id)) {
      if (placement === 'top') {
        const insertAt = Math.max(0, state.nowPlayingIndex + 1);
        playlist = [
          ...playlist.slice(0, insertAt),
          request.track,
          ...playlist.slice(insertAt),
        ];
      } else {
        playlist = [...playlist, request.track];
      }
    }
    set({ state: { ...state, pendingRequests, playlist } });
    get().broadcastState();
  },

  rejectRequest: (requestId) => {
    const state = get().state;
    set({
      state: {
        ...state,
        pendingRequests: state.pendingRequests.filter((r) => r.id !== requestId),
      },
    });
    get().broadcastState();
  },

  approveConnector: (deviceId) => {
    const pending = get().pendingConnections.filter((c) => c.deviceId !== deviceId);
    const state = get().state;
    const connectors = state.connectors.map((c) =>
      c.deviceId === deviceId ? { ...c, approved: true } : c,
    );
    const existing = connectors.find((c) => c.deviceId === deviceId);
    const fromPending = get().pendingConnections.find((c) => c.deviceId === deviceId);
    const nextConnectors = existing
      ? connectors
      : fromPending
        ? [...connectors, { ...fromPending, approved: true }]
        : connectors;
    set({
      pendingConnections: pending,
      state: { ...state, connectors: nextConnectors },
    });
    get().broadcastState();
  },

  rejectConnector: (deviceId) => {
    set({
      pendingConnections: get().pendingConnections.filter((c) => c.deviceId !== deviceId),
      state: {
        ...get().state,
        connectors: get().state.connectors.filter((c) => c.deviceId !== deviceId),
      },
    });
    get().broadcastState();
  },

  refreshJoinCode: async () => {
    const { sessionId, sessionToken, serverUrl, joinCode } = get();
    if (!sessionId || !sessionToken) return;
    if (joinCode && /^[A-Z0-9]{6}$/.test(joinCode)) return;
    const code = await fetchHostJoinCode({ sessionId, sessionToken, serverUrl });
    if (!code) return;
    const stored = get().storedSession;
    if (stored) {
      const next = { ...stored, joinCode: code };
      saveStored(next);
      set({ joinCode: code, storedSession: next });
    } else {
      set({ joinCode: code });
    }
  },
}));

type HostStoreSet = (
  partial: Partial<HostSessionStore> | ((s: HostSessionStore) => Partial<HostSessionStore>),
) => void;
type HostStoreGet = () => HostSessionStore;

function handleHostMessage(
  message: Record<string, unknown>,
  set: HostStoreSet,
  get: HostStoreGet,
): void {
  const type = message.type as string;
  const payload = message.payload as Record<string, unknown> | undefined;

  switch (type) {
    case 'host.started': {
      const sessionId = String(payload?.sessionId ?? '');
      const sessionToken = String(payload?.sessionToken ?? '');
      const joinCode = String(payload?.joinCode ?? '')
        .trim()
        .toUpperCase() || null;
      const serverUrl = String(payload?.serverUrl ?? get().serverUrl);
      const stored: StoredHostSession = {
        sessionId,
        sessionToken,
        serverUrl,
        hostGoogleSub: get().hostGoogleSub || '',
        joinCode: joinCode ?? undefined,
      };
      saveStored(stored);
      set({
        connected: true,
        sessionId,
        sessionToken,
        joinCode,
        serverUrl,
        storedSession: stored,
        error: null,
      });
      if (!joinCode) void get().refreshJoinCode();
      break;
    }
    case 'host.reconnected': {
      const joinCode = String(payload?.joinCode ?? '')
        .trim()
        .toUpperCase();
      const patch: Partial<HostSessionStore> = {
        connected: true,
        error: null,
      };
      if (joinCode && /^[A-Z0-9]{6}$/.test(joinCode)) {
        patch.joinCode = joinCode;
        const stored = get().storedSession;
        if (stored) {
          const next = { ...stored, joinCode };
          saveStored(next);
          patch.storedSession = next;
        }
      }
      if (payload?.state) patch.state = payload.state as unknown as HostState;
      set(patch);
      if (!get().joinCode) void get().refreshJoinCode();
      break;
    }
    case 'session.ended':
      saveStored(null);
      set({
        connected: false,
        storedSession: null,
        error: 'Session ended',
      });
      break;
    case 'error':
      set({ error: String(payload?.message ?? 'Relay error') });
      break;
    case 'relay': {
      const original = (payload?.original ?? {}) as Record<string, unknown>;
      handleRelay(original, set, get);
      break;
    }
    default:
      break;
  }
}

function handleRelay(
  original: Record<string, unknown>,
  set: HostStoreSet,
  get: HostStoreGet,
): void {
  const type = original.type as string;
  const payload = (original.payload ?? {}) as Record<string, unknown>;
  const from = (original.from ?? {}) as { deviceId?: string; displayName?: string };

  switch (type) {
    case 'connector.join': {
      const deviceId = String(from.deviceId ?? payload.deviceId ?? '');
      const displayName = String(from.displayName ?? payload.displayName ?? 'Guest');
      if (!deviceId) return;
      const requireApproval = get().state.settings.requireConnectionApproval;
      const connector: ConnectorInfo = {
        deviceId,
        displayName,
        approved: !requireApproval,
      };
      const state = get().state;
      const without = state.connectors.filter((c) => c.deviceId !== deviceId);
      if (requireApproval) {
        const pending = [
          ...get().pendingConnections.filter((c) => c.deviceId !== deviceId),
          connector,
        ];
        set({
          pendingConnections: pending,
          state: { ...state, connectors: [...without, { ...connector, approved: false }] },
        });
      } else {
        set({
          state: { ...state, connectors: [...without, connector] },
        });
      }
      get().broadcastState();
      break;
    }
    case 'connector.leave': {
      const deviceId = String(payload.deviceId ?? from.deviceId ?? '');
      if (!deviceId) return;
      set({
        pendingConnections: get().pendingConnections.filter((c) => c.deviceId !== deviceId),
        state: {
          ...get().state,
          connectors: get().state.connectors.filter((c) => c.deviceId !== deviceId),
        },
      });
      get().broadcastState();
      break;
    }
    case 'connector.request': {
      const deviceId = String(from.deviceId ?? '');
      const displayName = String(from.displayName ?? 'Guest');
      const track = payload.track as Track | undefined;
      if (!deviceId || !track) return;
      const state = get().state;
      const connector = state.connectors.find((c) => c.deviceId === deviceId);
      if (state.settings.requireConnectionApproval && !connector?.approved) {
        return;
      }
      if (!state.settings.allowSuggestions) return;
      if (state.settings.autoApproveRequests) {
        const playlist = state.playlist.some((t) => t.id === track.id)
          ? state.playlist
          : [...state.playlist, track];
        set({ state: { ...state, playlist } });
        get().broadcastState();
        return;
      }
      const request = {
        id: uuid(),
        track,
        requestedBy: displayName,
        deviceId,
        requestedAt: Date.now(),
      };
      set({
        state: {
          ...state,
          pendingRequests: [...state.pendingRequests, request],
        },
      });
      get().broadcastState();
      break;
    }
    case 'connector.vote': {
      const songId = String(payload.songId ?? '');
      const action = payload.action as 'add' | 'remove';
      if (!songId || !get().state.settings.allowVoting) return;
      const voteScores = { ...get().state.voteScores };
      const current = voteScores[songId] ?? 0;
      voteScores[songId] = action === 'add' ? current + 1 : Math.max(0, current - 1);
      set({ state: { ...get().state, voteScores } });
      get().broadcastState();
      break;
    }
    default:
      break;
  }
}

function waitUntil(predicate: () => boolean, timeoutMs: number): Promise<void> {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const tick = () => {
      if (predicate()) return resolve();
      if (Date.now() - start > timeoutMs) {
        return reject(new Error('Timed out waiting for session'));
      }
      setTimeout(tick, 100);
    };
    tick();
  });
}
