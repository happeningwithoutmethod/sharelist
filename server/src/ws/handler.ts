import type { WebSocket } from 'ws';
import {
  clientMessageSchema,
  type ClientMessage,
  type RelayedClientMessage,
  type ServerMessage,
} from '../protocol/messages.js';
import type { PlayLog } from '../play-log.js';
import { SessionStore } from '../session/store.js';

interface ClientMeta {
  role: 'host' | 'connector' | 'unknown';
  sessionId?: string;
  deviceId?: string;
}

export class WebSocketHandler {
  private clientMeta = new WeakMap<WebSocket, ClientMeta>();
  private serverPublicUrl: string;

  constructor(
    private store: SessionStore,
    serverPublicUrl: string,
    private playLog?: PlayLog,
  ) {
    this.serverPublicUrl = serverPublicUrl;
    this.store.setOnSessionEnd((sessionId, reason, session) => {
      this.playLog?.clearSessionCountry(sessionId);
      this.broadcastSessionEnded(sessionId, reason, session);
    });
  }

  handleConnection(socket: WebSocket): void {
    this.clientMeta.set(socket, { role: 'unknown' });

    socket.on('message', (data) => {
      try {
        const parsed = JSON.parse(data.toString());
        const message = clientMessageSchema.parse(parsed);
        this.handleMessage(socket, message);
      } catch (error) {
        this.send(socket, {
          type: 'error',
          payload: {
            code: 'INVALID_MESSAGE',
            message: error instanceof Error ? error.message : 'Invalid message',
          },
        });
      }
    });

    socket.on('close', () => {
      this.handleDisconnect(socket);
    });
  }

  private handleMessage(socket: WebSocket, message: ClientMessage): void {
    switch (message.type) {
      case 'ping':
        this.send(socket, { type: 'pong', sessionId: message.sessionId });
        return;
      case 'host.start':
        this.handleHostStart(socket, message);
        return;
      case 'host.reconnect':
        this.handleHostReconnect(socket, message);
        return;
      case 'host.end':
        this.handleHostEnd(socket, message);
        return;
      case 'connector.join':
        this.handleConnectorJoin(socket, message);
        return;
      case 'connector.leave':
        this.handleConnectorLeave(socket, message);
        return;
      case 'host.state':
        this.handleHostState(socket, message);
        return;
      default:
        this.relayMessage(socket, message);
    }
  }

  private handleHostStart(
    socket: WebSocket,
    message: Extract<ClientMessage, { type: 'host.start' }>,
  ): void {
    const countryCode = message.payload.countryCode?.trim() || 'unknown';
    const session = this.store.createSession(
      message.payload.hostGoogleSub,
      message.payload.sessionName,
      countryCode,
    );
    this.store.attachHost(session.id, socket);
    this.clientMeta.set(socket, { role: 'host', sessionId: session.id });
    this.playLog?.setSessionCountry(session.id, countryCode);

    this.send(socket, {
      type: 'host.started',
      sessionId: session.id,
      payload: {
        sessionId: session.id,
        sessionToken: session.sessionToken,
        joinCode: session.joinCode,
        serverUrl: this.serverPublicUrl,
      },
    });
  }

  private handleHostReconnect(
    socket: WebSocket,
    message: Extract<ClientMessage, { type: 'host.reconnect' }>,
  ): void {
    let session = this.store.getSession(message.payload.sessionId);
    let recreated = false;

    if (!session) {
      // Relay restarts wipe in-memory sessions; recreate with the host's
      // stable id/token so share links keep working.
      session = this.store.restoreSession({
        sessionId: message.payload.sessionId,
        sessionToken: message.payload.sessionToken,
        hostGoogleSub: message.payload.hostGoogleSub,
        countryCode: message.payload.countryCode,
        stateSnapshot: message.payload.state,
      });
      recreated = true;
    } else {
      if (session.sessionToken !== message.payload.sessionToken) {
        this.send(socket, {
          type: 'error',
          payload: { code: 'INVALID_TOKEN', message: 'Invalid session token' },
        });
        return;
      }

      if (session.hostGoogleSub !== message.payload.hostGoogleSub) {
        this.send(socket, {
          type: 'error',
          payload: { code: 'UNAUTHORIZED', message: 'Host account mismatch' },
        });
        return;
      }

      if (session.status === 'ended') {
        this.send(socket, {
          type: 'error',
          payload: { code: 'SESSION_ENDED', message: 'Session has ended' },
        });
        return;
      }
    }

    this.store.attachHost(session.id, socket);
    this.clientMeta.set(socket, { role: 'host', sessionId: session.id });
    if (message.payload.countryCode) {
      this.playLog?.setSessionCountry(session.id, message.payload.countryCode);
    }

    // Prefer the live host playlist when the session was just recreated.
    if (recreated && message.payload.state) {
      this.store.updateStateSnapshot(session.id, message.payload.state);
      session = this.store.getSession(session.id) ?? session;
    }

    this.send(socket, {
      type: 'host.reconnected',
      sessionId: session.id,
      payload: {
        state: session.stateSnapshot,
        recreated,
        joinCode: session.joinCode,
        serverUrl: this.serverPublicUrl,
      },
    });
  }

  private handleHostEnd(
    socket: WebSocket,
    message: Extract<ClientMessage, { type: 'host.end' }>,
  ): void {
    const session = this.store.getSession(message.sessionId);
    if (!session || session.hostSocket !== socket) {
      this.send(socket, {
        type: 'error',
        payload: { code: 'UNAUTHORIZED', message: 'Not the session host' },
      });
      return;
    }

    this.store.destroySession(message.sessionId, 'host_ended');
  }

  private handleConnectorJoin(
    socket: WebSocket,
    message: Extract<ClientMessage, { type: 'connector.join' }>,
  ): void {
    const result = this.store.addConnector(
      message.sessionId,
      message.payload.deviceId,
      message.payload.displayName,
      socket,
    );

    if (!result.ok) {
      this.send(socket, {
        type: 'error',
        sessionId: message.sessionId,
        payload: { code: 'JOIN_FAILED', message: result.error },
      });
      return;
    }

    this.clientMeta.set(socket, {
      role: 'connector',
      sessionId: message.sessionId,
      deviceId: message.payload.deviceId,
    });

    this.send(socket, {
      type: 'connector.joined',
      sessionId: message.sessionId,
      payload: {
        deviceId: message.payload.deviceId,
        displayName: message.payload.displayName,
        state: result.session.stateSnapshot,
      },
    });

    // Rejoins after a dropped socket keep host-side approval; only notify on first join.
    if (!result.reconnected) {
      this.relayToHost(message.sessionId, message);
    }
  }

  private handleConnectorLeave(
    socket: WebSocket,
    message: Extract<ClientMessage, { type: 'connector.leave' }>,
  ): void {
    const meta = this.clientMeta.get(socket);
    if (!meta?.deviceId) return;

    const connector = this.store.removeConnector(message.sessionId, meta.deviceId);
    this.relayToHost(message.sessionId, {
      ...message,
      payload: {
        deviceId: meta.deviceId,
        displayName: connector?.displayName,
      },
    });
  }

  private handleHostState(
    socket: WebSocket,
    message: Extract<ClientMessage, { type: 'host.state' }>,
  ): void {
    const session = this.store.getSession(message.sessionId);
    if (!session || session.hostSocket !== socket) {
      this.send(socket, {
        type: 'error',
        payload: { code: 'UNAUTHORIZED', message: 'Not the session host' },
      });
      return;
    }

    const previous = session.stateSnapshot;
    this.store.updateStateSnapshot(message.sessionId, message.payload);
    this.playLog?.observeHostState({
      sessionId: message.sessionId,
      previous,
      next: message.payload,
    });
    this.broadcastToConnectors(message.sessionId, {
      type: 'host.state',
      sessionId: message.sessionId,
      payload: message.payload,
    });
  }

  private relayMessage(socket: WebSocket, message: ClientMessage): void {
    const meta = this.clientMeta.get(socket);
    if (!meta?.sessionId) {
      this.send(socket, {
        type: 'error',
        payload: { code: 'NOT_IN_SESSION', message: 'Not connected to a session' },
      });
      return;
    }

    const session = this.store.getSession(meta.sessionId);
    if (!session) {
      this.send(socket, {
        type: 'error',
        sessionId: meta.sessionId,
        payload: { code: 'SESSION_NOT_FOUND', message: 'Session not found' },
      });
      return;
    }

    if (meta.role === 'connector') {
      if (session.hostSocket && session.hostSocket.readyState === session.hostSocket.OPEN) {
        const connector = session.connectors.get(meta.deviceId ?? '');
        const original: RelayedClientMessage = {
          ...message,
          from: {
            deviceId: meta.deviceId,
            displayName: connector?.displayName,
          },
        };
        this.send(session.hostSocket, {
          type: 'relay',
          sessionId: meta.sessionId,
          payload: { original },
        });
      }
      return;
    }

    if (meta.role === 'host') {
      this.broadcastToConnectors(meta.sessionId, {
        type: 'relay',
        sessionId: meta.sessionId,
        payload: { original: message },
      });
    }
  }

  private relayToHost(sessionId: string, message: ClientMessage): void {
    const session = this.store.getSession(sessionId);
    if (session?.hostSocket && session.hostSocket.readyState === session.hostSocket.OPEN) {
      let original: RelayedClientMessage = message;
      if (message.type === 'connector.join') {
        original = {
          ...message,
          from: {
            deviceId: message.payload.deviceId,
            displayName: message.payload.displayName,
          },
        };
      }

      this.send(session.hostSocket, {
        type: 'relay',
        sessionId,
        payload: { original },
      });
    }
  }

  private handleDisconnect(socket: WebSocket): void {
    const meta = this.clientMeta.get(socket);
    if (!meta?.sessionId) return;

    if (meta.role === 'host') {
      const session = this.store.getSession(meta.sessionId);
      if (session?.hostSocket === socket) {
        this.store.orphanSession(meta.sessionId);
      }
      return;
    }

    if (meta.role === 'connector' && meta.deviceId) {
      // Soft-detach so the same device can reconnect without re-approval.
      this.store.detachConnectorSocket(meta.sessionId, socket);
    }
  }

  private broadcastToConnectors(sessionId: string, message: ServerMessage): void {
    const session = this.store.getSession(sessionId);
    if (!session) return;

    for (const connector of session.connectors.values()) {
      if (connector.socket && connector.socket.readyState === connector.socket.OPEN) {
        this.send(connector.socket, message);
      }
    }
  }

  private broadcastSessionEnded(
    sessionId: string,
    reason: 'host_ended' | 'expired' | 'error',
    session: import('../session/store.js').Session,
  ): void {
    const message: ServerMessage = {
      type: 'session.ended',
      sessionId,
      payload: {
        reason,
        message:
          reason === 'expired'
            ? 'Session expired after host disconnect'
            : reason === 'host_ended'
              ? 'Host ended the session'
              : 'Session ended due to an error',
      },
    };

    if (session.hostSocket && session.hostSocket.readyState === session.hostSocket.OPEN) {
      this.send(session.hostSocket, message);
    }

    for (const connector of session.connectors.values()) {
      if (connector.socket && connector.socket.readyState === connector.socket.OPEN) {
        this.send(connector.socket, message);
      }
    }
  }

  private send(socket: WebSocket, message: ServerMessage): void {
    if (socket.readyState === socket.OPEN) {
      socket.send(JSON.stringify({ ...message, ts: Date.now() }));
    }
  }
}
