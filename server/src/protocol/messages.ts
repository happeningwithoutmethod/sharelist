import { z } from 'zod';

export const MAX_CONNECTORS = 50;
export const ORPHAN_TTL_MS = 30 * 60 * 1000;

export const trackSchema = z
  .object({
    id: z.string(),
    title: z.string(),
    artist: z.string(),
    artworkUrl: z.string().nullish(),
    sourceUrl: z.string(),
    provider: z.string(),
  })
  .passthrough();

export const hostSettingsSchema = z.object({
  allowSuggestions: z.boolean(),
  allowVoting: z.boolean(),
  autoReorderByVotes: z.boolean(),
  autoPlaylistAdvance: z.boolean().default(true),
  autoApproveRequests: z.boolean().default(false),
  requireConnectionApproval: z.boolean().default(false),
}).passthrough();

export const hostStateSchema = z
  .object({
    sessionName: z.string(),
    playlist: z.array(trackSchema),
    nowPlayingIndex: z.number().int().min(-1),
    isPlaying: z.boolean(),
    positionMs: z.number().int().min(0),
    durationMs: z.number().int().min(0),
    settings: hostSettingsSchema,
    voteScores: z.record(z.string(), z.number()).default({}),
    pendingRequests: z.array(
      z.object({
        id: z.string(),
        track: trackSchema,
        requestedBy: z.string(),
        deviceId: z.string(),
        requestedAt: z.number(),
      }),
    ),
    connectors: z.array(
      z.object({
        deviceId: z.string(),
        displayName: z.string(),
        approved: z.boolean().default(true),
      }),
    ),
  })
  .passthrough();

export type HostState = z.infer<typeof hostStateSchema>;
export type Track = z.infer<typeof trackSchema>;

const baseMessage = {
  sessionId: z.string().optional(),
  ts: z.number().optional(),
};

export const clientMessageSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('host.start'),
    ...baseMessage,
    payload: z.object({
      hostGoogleSub: z.string(),
      sessionName: z.string().optional(),
      /** ISO 3166-1 alpha-2, or "unknown" when location is unavailable. */
      countryCode: z.string().min(1).max(16).optional(),
    }),
  }),
  z.object({
    type: z.literal('host.reconnect'),
    ...baseMessage,
    payload: z.object({
      sessionId: z.string(),
      sessionToken: z.string(),
      hostGoogleSub: z.string(),
      /** Used when recreating a session after a relay restart. */
      countryCode: z.string().min(1).max(16).optional(),
      state: hostStateSchema.optional(),
    }),
  }),
  z.object({
    type: z.literal('host.end'),
    sessionId: z.string(),
    payload: z.object({}).optional(),
  }),
  z.object({
    type: z.literal('host.state'),
    sessionId: z.string(),
    payload: hostStateSchema,
  }),
  z.object({
    type: z.literal('host.approve'),
    sessionId: z.string(),
    payload: z.object({
      requestId: z.string(),
      placement: z.enum(['top', 'bottom']),
    }),
  }),
  z.object({
    type: z.literal('host.playback'),
    sessionId: z.string(),
    payload: z.object({
      action: z.enum(['play', 'pause', 'next', 'previous', 'seek']),
      positionMs: z.number().optional(),
    }),
  }),
  z.object({
    type: z.literal('host.settings'),
    sessionId: z.string(),
    payload: hostSettingsSchema.partial(),
  }),
  z.object({
    type: z.literal('connector.join'),
    sessionId: z.string(),
    payload: z.object({
      displayName: z.string().min(1).max(50),
      deviceId: z.string(),
    }),
  }),
  z.object({
    type: z.literal('connector.leave'),
    sessionId: z.string(),
    payload: z.object({}).optional(),
  }),
  z.object({
    type: z.literal('connector.request'),
    sessionId: z.string(),
    payload: z.object({
      track: trackSchema,
    }),
  }),
  z.object({
    type: z.literal('connector.vote'),
    sessionId: z.string(),
    payload: z.object({
      songId: z.string(),
      action: z.enum(['add', 'remove']),
    }),
  }),
  z.object({
    type: z.literal('ping'),
    sessionId: z.string().optional(),
    payload: z.object({}).optional(),
  }),
]);

export type ClientMessage = z.infer<typeof clientMessageSchema>;

/** Optional sender metadata attached when the relay forwards connector traffic. */
export const relayFromSchema = z.object({
  deviceId: z.string().optional(),
  displayName: z.string().optional(),
});

export type RelayFrom = z.infer<typeof relayFromSchema>;

/** Client message as seen inside a `relay` envelope (may include `from`). */
export type RelayedClientMessage = ClientMessage & {
  from?: RelayFrom;
};

export const serverMessageSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('host.started'),
    sessionId: z.string(),
    payload: z.object({
      sessionId: z.string(),
      sessionToken: z.string(),
      joinCode: z.string().optional(),
      serverUrl: z.string(),
    }),
  }),
  z.object({
    type: z.literal('host.reconnected'),
    sessionId: z.string(),
    payload: z.object({
      state: hostStateSchema,
      /** True when the relay recreated the session (e.g. after a restart). */
      recreated: z.boolean().optional(),
      joinCode: z.string().optional(),
      serverUrl: z.string().optional(),
    }),
  }),
  z.object({
    type: z.literal('session.ended'),
    sessionId: z.string(),
    payload: z.object({
      reason: z.enum(['host_ended', 'expired', 'error']),
      message: z.string().optional(),
    }),
  }),
  z.object({
    type: z.literal('host.state'),
    sessionId: z.string(),
    payload: hostStateSchema,
  }),
  z.object({
    type: z.literal('connector.joined'),
    sessionId: z.string(),
    payload: z.object({
      deviceId: z.string(),
      displayName: z.string(),
      state: hostStateSchema,
    }),
  }),
  z.object({
    type: z.literal('connector.left'),
    sessionId: z.string(),
    payload: z.object({
      deviceId: z.string(),
    }),
  }),
  z.object({
    type: z.literal('relay'),
    sessionId: z.string(),
    payload: z.object({
      // Keep validation loose enough for optional `from` metadata.
      original: z.intersection(
        clientMessageSchema,
        z.object({ from: relayFromSchema.optional() }),
      ),
    }),
  }),
  z.object({
    type: z.literal('error'),
    sessionId: z.string().optional(),
    payload: z.object({
      code: z.string(),
      message: z.string(),
    }),
  }),
  z.object({
    type: z.literal('pong'),
    sessionId: z.string().optional(),
    payload: z.object({}).optional(),
  }),
]);

export type ServerMessage = z.infer<typeof serverMessageSchema>;

export function createEmptyHostState(sessionName = 'Share List Session'): HostState {
  return {
    sessionName,
    playlist: [],
    nowPlayingIndex: -1,
    isPlaying: false,
    positionMs: 0,
    durationMs: 0,
    settings: {
      allowSuggestions: true,
      allowVoting: true,
      autoReorderByVotes: false,
      autoPlaylistAdvance: true,
      autoApproveRequests: false,
      requireConnectionApproval: false,
    },
    voteScores: {},
    pendingRequests: [],
    connectors: [],
  };
}
