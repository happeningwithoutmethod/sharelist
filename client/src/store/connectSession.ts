import { create } from 'zustand';
import { createEmptyHostState, type HostState, type Track } from '../protocol/types';
import { SessionClient } from '../ws/sessionClient';
import { normalizeServerUrl } from '../api/relay';
import { WS_URL } from '../config';

const NAME_KEY = 'sharelist.displayName';
const SAVED_KEY = 'sharelist.savedConnections';

export interface SavedConnection {
  sessionId: string;
  serverUrl: string;
  sessionName: string;
  lastConnectedAt: number;
}

function loadName(): string {
  return localStorage.getItem(NAME_KEY) || '';
}

function loadSaved(): SavedConnection[] {
  try {
    const raw = localStorage.getItem(SAVED_KEY);
    return raw ? (JSON.parse(raw) as SavedConnection[]) : [];
  } catch {
    return [];
  }
}

function rememberConnection(conn: SavedConnection): void {
  const list = loadSaved().filter(
    (c) => !(c.sessionId === conn.sessionId && c.serverUrl === conn.serverUrl),
  );
  list.unshift(conn);
  localStorage.setItem(SAVED_KEY, JSON.stringify(list.slice(0, 20)));
}

interface ConnectSessionStore {
  connected: boolean;
  busy: boolean;
  error: string | null;
  sessionId: string | null;
  serverUrl: string;
  displayName: string;
  deviceId: string;
  state: HostState;
  votedSongIds: globalThis.Set<string>;
  client: SessionClient | null;
  savedConnections: SavedConnection[];
  approved: boolean;

  setDisplayName: (name: string) => void;
  join: (input: {
    sessionId: string;
    serverUrl: string;
    displayName: string;
    deviceId: string;
  }) => Promise<void>;
  leave: () => Promise<void>;
  requestTrack: (track: Track) => void;
  toggleVote: (songId: string) => void;
  removeSaved: (sessionId: string, serverUrl: string) => void;
  clearError: () => void;
}

export const useConnectStore = create<ConnectSessionStore>((set, get) => ({
  connected: false,
  busy: false,
  error: null,
  sessionId: null,
  serverUrl: WS_URL,
  displayName: loadName(),
  deviceId: '',
  state: createEmptyHostState(),
  votedSongIds: new globalThis.Set(),
  client: null,
  savedConnections: loadSaved(),
  approved: true,

  clearError: () => set({ error: null }),

  setDisplayName: (name) => {
    localStorage.setItem(NAME_KEY, name);
    set({ displayName: name });
  },

  join: async ({ sessionId, serverUrl, displayName, deviceId }) => {
    const resolved = normalizeServerUrl(serverUrl || WS_URL);
    set({
      busy: true,
      error: null,
      sessionId,
      serverUrl: resolved,
      displayName,
      deviceId,
      connected: false,
      votedSongIds: new globalThis.Set(),
    });
    localStorage.setItem(NAME_KEY, displayName);

    const client = new SessionClient(resolved);
    client.addHandler((message) => handleConnectMessage(message, set, get));
    client.setDisconnectListener(() => {
      if (get().sessionId) {
        set({ connected: false, error: 'Connection to the session was lost' });
      }
    });

    try {
      await client.connect();
      set({ client });
      client.send({
        type: 'connector.join',
        sessionId,
        payload: { displayName, deviceId },
      });
      await waitUntil(() => get().connected, 10_000);
      rememberConnection({
        sessionId,
        serverUrl: resolved,
        sessionName: get().state.sessionName || 'Share List Session',
        lastConnectedAt: Date.now(),
      });
      set({ savedConnections: loadSaved() });
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

  leave: async () => {
    const { client, sessionId } = get();
    if (client && sessionId) {
      client.send({ type: 'connector.leave', sessionId, payload: {} });
    }
    await client?.disconnect();
    set({
      connected: false,
      client: null,
      sessionId: null,
      state: createEmptyHostState(),
      votedSongIds: new globalThis.Set(),
    });
  },

  requestTrack: (track) => {
    const { client, sessionId, approved, state } = get();
    if (!client || !sessionId) return;
    if (!approved && state.settings.requireConnectionApproval) {
      set({ error: 'Waiting for host to approve your connection' });
      return;
    }
    client.send({
      type: 'connector.request',
      sessionId,
      payload: { track },
    });
  },

  toggleVote: (songId) => {
    const { client, sessionId, votedSongIds, state } = get();
    if (!client || !sessionId || !state.settings.allowVoting) return;
    const next = new globalThis.Set(votedSongIds);
    const action = next.has(songId) ? 'remove' : 'add';
    if (action === 'add') next.add(songId);
    else next.delete(songId);
    set({ votedSongIds: next });
    client.send({
      type: 'connector.vote',
      sessionId,
      payload: { songId, action },
    });
  },

  removeSaved: (sessionId, serverUrl) => {
    const list = loadSaved().filter(
      (c) => !(c.sessionId === sessionId && c.serverUrl === serverUrl),
    );
    localStorage.setItem(SAVED_KEY, JSON.stringify(list));
    set({ savedConnections: list });
  },
}));

type StoreSet = (
  partial:
    | Partial<ConnectSessionStore>
    | ((s: ConnectSessionStore) => Partial<ConnectSessionStore>),
) => void;
type StoreGet = () => ConnectSessionStore;

function handleConnectMessage(
  message: Record<string, unknown>,
  set: StoreSet,
  get: StoreGet,
): void {
  const type = message.type as string;
  const payload = message.payload as Record<string, unknown> | undefined;

  switch (type) {
    case 'connector.joined': {
      const state = (payload?.state ?? createEmptyHostState()) as HostState;
      const deviceId = get().deviceId;
      const me = state.connectors.find((c) => c.deviceId === deviceId);
      set({
        connected: true,
        state,
        approved: me?.approved ?? !state.settings.requireConnectionApproval,
        error: null,
      });
      break;
    }
    case 'host.state':
      if (payload) {
        const state = payload as unknown as HostState;
        const me = state.connectors.find((c) => c.deviceId === get().deviceId);
        set({
          state,
          approved: me?.approved ?? get().approved,
        });
      }
      break;
    case 'session.ended':
      set({
        connected: false,
        error: String(payload?.message ?? 'Session ended'),
      });
      break;
    case 'error':
      set({ error: String(payload?.message ?? 'Could not join') });
      break;
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
        return reject(new Error(getError() || 'Timed out waiting to join'));
      }
      setTimeout(tick, 100);
    };
    const getError = () => useConnectStore.getState().error;
    tick();
  });
}
