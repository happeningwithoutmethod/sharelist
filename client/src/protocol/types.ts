export interface Track {
  id: string;
  title: string;
  artist: string;
  artworkUrl?: string | null;
  sourceUrl: string;
  provider: string;
}

export interface HostSettings {
  allowSuggestions: boolean;
  allowVoting: boolean;
  autoReorderByVotes: boolean;
  autoPlaylistAdvance: boolean;
  autoApproveRequests: boolean;
  requireConnectionApproval: boolean;
}

export interface SongRequest {
  id: string;
  track: Track;
  requestedBy: string;
  deviceId: string;
  requestedAt: number;
}

export interface ConnectorInfo {
  deviceId: string;
  displayName: string;
  approved: boolean;
}

export interface HostState {
  sessionName: string;
  playlist: Track[];
  nowPlayingIndex: number;
  isPlaying: boolean;
  positionMs: number;
  durationMs: number;
  settings: HostSettings;
  voteScores: Record<string, number>;
  pendingRequests: SongRequest[];
  connectors: ConnectorInfo[];
}

export function createEmptyHostState(
  sessionName = 'Share List Session',
): HostState {
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

export type WireMessage = {
  type: string;
  sessionId?: string;
  payload?: unknown;
  ts?: number;
  from?: { deviceId?: string; displayName?: string };
};
