import { randomUUID } from 'node:crypto';
import type { WebSocket } from 'ws';
import {
  MAX_CONNECTORS,
  ORPHAN_TTL_MS,
  createEmptyHostState,
  type HostState,
} from '../protocol/messages.js';
import { isJoinCode, normalizeJoinCode, randomJoinCode } from './join-code.js';

export type SessionStatus = 'active' | 'orphaned' | 'ended';

export interface ConnectorInfo {
  deviceId: string;
  displayName: string;
  socket: WebSocket | null;
}

export interface Session {
  id: string;
  sessionToken: string;
  /** Short public join code (6× A–Z0–9), unique among live sessions. */
  joinCode: string;
  hostGoogleSub: string;
  /** ISO country code from the host device, or "unknown". */
  countryCode: string;
  status: SessionStatus;
  hostSocket: WebSocket | null;
  connectors: Map<string, ConnectorInfo>;
  stateSnapshot: HostState;
  orphanedAt: number | null;
  destroyTimer: NodeJS.Timeout | null;
}

export type SessionEndReason = 'host_ended' | 'expired' | 'error';

export class SessionStore {
  private sessions = new Map<string, Session>();
  /** joinCode → sessionId */
  private joinCodes = new Map<string, string>();
  private onSessionEnd?: (
    sessionId: string,
    reason: SessionEndReason,
    session: Session,
  ) => void;

  setOnSessionEnd(
    callback: (sessionId: string, reason: SessionEndReason, session: Session) => void,
  ) {
    this.onSessionEnd = callback;
  }

  private allocateJoinCode(): string {
    for (let attempt = 0; attempt < 200; attempt++) {
      const code = randomJoinCode();
      if (!this.joinCodes.has(code)) {
        return code;
      }
    }
    throw new Error('Could not allocate a unique join code');
  }

  private registerJoinCode(session: Session): void {
    this.joinCodes.set(session.joinCode, session.id);
  }

  private unregisterJoinCode(session: Session): void {
    const mapped = this.joinCodes.get(session.joinCode);
    if (mapped === session.id) {
      this.joinCodes.delete(session.joinCode);
    }
  }

  createSession(
    hostGoogleSub: string,
    sessionName?: string,
    countryCode = 'unknown',
  ): Session {
    const id = randomUUID();
    const joinCode = this.allocateJoinCode();
    const session: Session = {
      id,
      sessionToken: randomUUID(),
      joinCode,
      hostGoogleSub,
      countryCode: countryCode.trim() || 'unknown',
      status: 'active',
      hostSocket: null,
      connectors: new Map(),
      stateSnapshot: createEmptyHostState(sessionName),
      orphanedAt: null,
      destroyTimer: null,
    };
    this.sessions.set(id, session);
    this.registerJoinCode(session);
    return session;
  }

  /**
   * Recreate a session with stable ids after a relay restart so existing
   * share links and host credentials keep working.
   */
  restoreSession(params: {
    sessionId: string;
    sessionToken: string;
    hostGoogleSub: string;
    countryCode?: string;
    stateSnapshot?: HostState;
    joinCode?: string;
  }): Session {
    const existing = this.sessions.get(params.sessionId);
    if (existing) return existing;

    let joinCode = params.joinCode ? normalizeJoinCode(params.joinCode) : '';
    if (!isJoinCode(joinCode) || this.joinCodes.has(joinCode)) {
      joinCode = this.allocateJoinCode();
    }

    const session: Session = {
      id: params.sessionId,
      sessionToken: params.sessionToken,
      joinCode,
      hostGoogleSub: params.hostGoogleSub,
      countryCode: (params.countryCode ?? 'unknown').trim() || 'unknown',
      status: 'active',
      hostSocket: null,
      connectors: new Map(),
      stateSnapshot: params.stateSnapshot ?? createEmptyHostState(),
      orphanedAt: null,
      destroyTimer: null,
    };
    this.sessions.set(params.sessionId, session);
    this.registerJoinCode(session);
    return session;
  }

  getSession(sessionId: string): Session | undefined {
    return this.sessions.get(sessionId);
  }

  getSessionByJoinCode(code: string): Session | undefined {
    const normalized = normalizeJoinCode(code);
    if (!isJoinCode(normalized)) return undefined;
    const sessionId = this.joinCodes.get(normalized);
    if (!sessionId) return undefined;
    return this.sessions.get(sessionId);
  }

  /** Snapshot of all sessions for the ops dashboard. */
  listSessions(): Session[] {
    return [...this.sessions.values()];
  }

  attachHost(sessionId: string, socket: WebSocket): Session | undefined {
    const session = this.sessions.get(sessionId);
    if (!session) return undefined;

    if (session.destroyTimer) {
      clearTimeout(session.destroyTimer);
      session.destroyTimer = null;
    }

    session.hostSocket = socket;
    session.status = 'active';
    session.orphanedAt = null;
    return session;
  }

  orphanSession(sessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (!session || session.status === 'ended') return;

    session.status = 'orphaned';
    session.hostSocket = null;
    session.orphanedAt = Date.now();

    if (session.destroyTimer) {
      clearTimeout(session.destroyTimer);
    }

    session.destroyTimer = setTimeout(() => {
      this.destroySession(sessionId, 'expired');
    }, ORPHAN_TTL_MS);
  }

  destroySession(sessionId: string, reason: SessionEndReason): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    session.status = 'ended';
    if (session.destroyTimer) {
      clearTimeout(session.destroyTimer);
      session.destroyTimer = null;
    }

    this.onSessionEnd?.(sessionId, reason, session);
    this.unregisterJoinCode(session);
    this.sessions.delete(sessionId);
  }

  updateStateSnapshot(sessionId: string, state: HostState): void {
    const session = this.sessions.get(sessionId);
    if (session) {
      session.stateSnapshot = state;
    }
  }

  addConnector(
    sessionId: string,
    deviceId: string,
    displayName: string,
    socket: WebSocket,
  ):
    | { ok: true; session: Session; reconnected: boolean }
    | { ok: false; error: string } {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return { ok: false, error: 'Session not found' };
    }
    if (session.status === 'ended') {
      return { ok: false, error: 'Session has ended' };
    }
    const alreadyJoined = session.connectors.has(deviceId);
    // New connectors cannot join while the host is offline; rejoining members can
    // reattach so a brief host blip does not permanently kick them.
    if (
      !alreadyJoined &&
      (session.status === 'orphaned' || session.hostSocket == null)
    ) {
      return { ok: false, error: 'Host is no longer available' };
    }
    if (!alreadyJoined && session.connectors.size >= MAX_CONNECTORS) {
      return { ok: false, error: 'Session is full' };
    }

    session.connectors.set(deviceId, { deviceId, displayName, socket });
    return { ok: true, session, reconnected: alreadyJoined };
  }

  /** Drop the live socket but keep membership so the same device can rejoin. */
  detachConnectorSocket(sessionId: string, socket: WebSocket): ConnectorInfo | undefined {
    const session = this.sessions.get(sessionId);
    if (!session) return undefined;

    for (const [deviceId, connector] of session.connectors) {
      if (connector.socket === socket) {
        session.connectors.set(deviceId, { ...connector, socket: null });
        return connector;
      }
    }
    return undefined;
  }

  removeConnector(sessionId: string, deviceId: string): ConnectorInfo | undefined {
    const session = this.sessions.get(sessionId);
    if (!session) return undefined;
    const connector = session.connectors.get(deviceId);
    if (connector) {
      session.connectors.delete(deviceId);
    }
    return connector;
  }

  removeConnectorBySocket(sessionId: string, socket: WebSocket): ConnectorInfo | undefined {
    const session = this.sessions.get(sessionId);
    if (!session) return undefined;

    for (const [deviceId, connector] of session.connectors) {
      if (connector.socket === socket) {
        session.connectors.delete(deviceId);
        return connector;
      }
    }
    return undefined;
  }

  findSessionByHostSocket(socket: WebSocket): Session | undefined {
    for (const session of this.sessions.values()) {
      if (session.hostSocket === socket) {
        return session;
      }
    }
    return undefined;
  }

  findSessionByConnectorSocket(socket: WebSocket): Session | undefined {
    for (const session of this.sessions.values()) {
      for (const connector of session.connectors.values()) {
        if (connector.socket === socket) {
          return session;
        }
      }
    }
    return undefined;
  }
}
