import { randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { HostState } from './protocol/messages.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEFAULT_DATA_PATH = join(__dirname, '..', 'data', 'play-log.json');
const MAX_EVENTS = 5000;
export const UNKNOWN_COUNTRY = 'unknown';

export interface PlayLogTrack {
  id: string;
  title: string;
  artist: string;
  artworkUrl?: string;
  provider?: string;
}

/** One recorded play of a song (UTC timestamp). */
export interface PlayEvent {
  id: string;
  /** ISO-8601 UTC timestamp when playback of this track started. */
  playedAt: string;
  sessionId: string;
  sessionName: string;
  track: PlayLogTrack;
  /** Vote/like count observed for this track when it started playing. */
  likes: number;
  /** ISO 3166-1 alpha-2 country code, or "unknown". */
  countryCode: string;
}

/** Aggregated stats per song across all sessions. */
export interface SongPlayStats {
  trackId: string;
  title: string;
  artist: string;
  artworkUrl?: string;
  provider?: string;
  playCount: number;
  /** Highest like count observed for this song. */
  likes: number;
  firstPlayedAt: string;
  lastPlayedAt: string;
}

export interface ArtistPlayStats {
  artist: string;
  playCount: number;
  uniqueSongs: number;
  likes: number;
  lastPlayedAt: string;
}

export interface CountrySongStats extends SongPlayStats {
  countryCode: string;
}

interface PlayLogFile {
  version: 1 | 2;
  events: PlayEvent[];
  aggregates: Record<string, SongPlayStats>;
}

function nowUtcIso(): string {
  return new Date().toISOString();
}

function normalizeCountry(code: string | undefined | null): string {
  const trimmed = code?.trim();
  if (!trimmed) return UNKNOWN_COUNTRY;
  if (trimmed.toLowerCase() === UNKNOWN_COUNTRY) return UNKNOWN_COUNTRY;
  return trimmed.toUpperCase();
}

function trackFromState(state: HostState): PlayLogTrack | null {
  const index = state.nowPlayingIndex;
  if (index < 0 || index >= state.playlist.length) return null;
  const track = state.playlist[index];
  return {
    id: track.id,
    title: track.title,
    artist: track.artist,
    artworkUrl: track.artworkUrl ?? undefined,
    provider: track.provider,
  };
}

export class PlayLog {
  private events: PlayEvent[] = [];
  private aggregates = new Map<string, SongPlayStats>();
  private readonly dataPath: string;
  private saveTimer: NodeJS.Timeout | null = null;
  /** sessionId → country code captured at host start */
  private sessionCountries = new Map<string, string>();

  constructor(dataPath = process.env.PLAY_LOG_PATH ?? DEFAULT_DATA_PATH) {
    this.dataPath = dataPath;
    this.load();
  }

  setSessionCountry(sessionId: string, countryCode: string | undefined): void {
    this.sessionCountries.set(sessionId, normalizeCountry(countryCode));
  }

  clearSessionCountry(sessionId: string): void {
    this.sessionCountries.delete(sessionId);
  }

  /**
   * Inspect a host.state transition. Records a play when the now-playing track
   * identity changes. Updates like counts from voteScores.
   */
  observeHostState(input: {
    sessionId: string;
    previous: HostState;
    next: HostState;
  }): PlayEvent | null {
    const { sessionId, previous, next } = input;
    this.updateLikesFromVotes(next.voteScores ?? {});

    const prevTrack = trackFromState(previous);
    const nextTrack = trackFromState(next);
    if (!nextTrack) return null;
    if (prevTrack?.id === nextTrack.id) return null;

    const looksLikeStart =
      next.isPlaying || next.positionMs <= 1500 || prevTrack == null;
    if (!looksLikeStart) return null;

    const likes = next.voteScores?.[nextTrack.id] ?? 0;
    return this.recordPlay({
      sessionId,
      sessionName: next.sessionName,
      track: nextTrack,
      likes,
      countryCode: this.sessionCountries.get(sessionId) ?? UNKNOWN_COUNTRY,
    });
  }

  recordPlay(input: {
    sessionId: string;
    sessionName: string;
    track: PlayLogTrack;
    likes: number;
    countryCode?: string;
  }): PlayEvent {
    const playedAt = nowUtcIso();
    const countryCode = normalizeCountry(input.countryCode);
    const event: PlayEvent = {
      id: randomUUID(),
      playedAt,
      sessionId: input.sessionId,
      sessionName: input.sessionName,
      track: input.track,
      likes: Math.max(0, input.likes),
      countryCode,
    };

    this.events.push(event);
    if (this.events.length > MAX_EVENTS) {
      this.events = this.events.slice(this.events.length - MAX_EVENTS);
    }

    const existing = this.aggregates.get(input.track.id);
    if (existing) {
      existing.playCount += 1;
      existing.likes = Math.max(existing.likes, event.likes);
      existing.lastPlayedAt = playedAt;
      existing.title = input.track.title;
      existing.artist = input.track.artist;
      if (input.track.artworkUrl) existing.artworkUrl = input.track.artworkUrl;
      if (input.track.provider) existing.provider = input.track.provider;
    } else {
      this.aggregates.set(input.track.id, {
        trackId: input.track.id,
        title: input.track.title,
        artist: input.track.artist,
        artworkUrl: input.track.artworkUrl,
        provider: input.track.provider,
        playCount: 1,
        likes: event.likes,
        firstPlayedAt: playedAt,
        lastPlayedAt: playedAt,
      });
    }

    this.scheduleSave();
    return event;
  }

  updateLikesFromVotes(voteScores: Record<string, number>): void {
    let changed = false;
    for (const [trackId, likes] of Object.entries(voteScores)) {
      const agg = this.aggregates.get(trackId);
      if (!agg) continue;
      const nextLikes = Math.max(0, likes);
      if (nextLikes > agg.likes) {
        agg.likes = nextLikes;
        changed = true;
      }
    }
    if (changed) this.scheduleSave();
  }

  /** Popular songs: play count desc, then likes desc, then most recent. */
  getPopularSongs(limit = 50): SongPlayStats[] {
    return [...this.aggregates.values()]
      .sort((a, b) => {
        if (b.playCount !== a.playCount) return b.playCount - a.playCount;
        if (b.likes !== a.likes) return b.likes - a.likes;
        return b.lastPlayedAt.localeCompare(a.lastPlayedAt);
      })
      .slice(0, limit);
  }

  getTopArtists(limit = 50): ArtistPlayStats[] {
    const byArtist = new Map<string, ArtistPlayStats & { songs: Set<string> }>();
    for (const event of this.events) {
      const artist = event.track.artist.trim() || 'Unknown artist';
      const key = artist.toLowerCase();
      const existing = byArtist.get(key);
      if (existing) {
        existing.playCount += 1;
        existing.likes = Math.max(existing.likes, event.likes);
        existing.lastPlayedAt =
          event.playedAt > existing.lastPlayedAt ? event.playedAt : existing.lastPlayedAt;
        existing.songs.add(event.track.id);
        existing.uniqueSongs = existing.songs.size;
      } else {
        byArtist.set(key, {
          artist,
          playCount: 1,
          uniqueSongs: 1,
          likes: event.likes,
          lastPlayedAt: event.playedAt,
          songs: new Set([event.track.id]),
        });
      }
    }

    return [...byArtist.values()]
      .map(({ songs: _songs, ...rest }) => rest)
      .sort((a, b) => {
        if (b.playCount !== a.playCount) return b.playCount - a.playCount;
        if (b.likes !== a.likes) return b.likes - a.likes;
        return b.lastPlayedAt.localeCompare(a.lastPlayedAt);
      })
      .slice(0, limit);
  }

  /** Best songs per country (top N overall countries by plays, top songs each). */
  getBestSongsByCountry(options?: {
    countries?: number;
    songsPerCountry?: number;
  }): Array<{ countryCode: string; songs: CountrySongStats[] }> {
    const countriesLimit = options?.countries ?? 12;
    const songsPerCountry = options?.songsPerCountry ?? 5;

    const perCountry = new Map<string, Map<string, CountrySongStats>>();
    for (const event of this.events) {
      const country = normalizeCountry(event.countryCode);
      let songs = perCountry.get(country);
      if (!songs) {
        songs = new Map();
        perCountry.set(country, songs);
      }
      const existing = songs.get(event.track.id);
      if (existing) {
        existing.playCount += 1;
        existing.likes = Math.max(existing.likes, event.likes);
        existing.lastPlayedAt = event.playedAt;
        existing.title = event.track.title;
        existing.artist = event.track.artist;
        if (event.track.artworkUrl) existing.artworkUrl = event.track.artworkUrl;
      } else {
        songs.set(event.track.id, {
          countryCode: country,
          trackId: event.track.id,
          title: event.track.title,
          artist: event.track.artist,
          artworkUrl: event.track.artworkUrl,
          provider: event.track.provider,
          playCount: 1,
          likes: event.likes,
          firstPlayedAt: event.playedAt,
          lastPlayedAt: event.playedAt,
        });
      }
    }

    const rankedCountries = [...perCountry.entries()]
      .map(([countryCode, songs]) => {
        const totalPlays = [...songs.values()].reduce((sum, song) => sum + song.playCount, 0);
        const topSongs = [...songs.values()]
          .sort((a, b) => {
            if (b.playCount !== a.playCount) return b.playCount - a.playCount;
            if (b.likes !== a.likes) return b.likes - a.likes;
            return b.lastPlayedAt.localeCompare(a.lastPlayedAt);
          })
          .slice(0, songsPerCountry);
        return { countryCode, totalPlays, songs: topSongs };
      })
      .sort((a, b) => b.totalPlays - a.totalPlays)
      .slice(0, countriesLimit);

    return rankedCountries.map(({ countryCode, songs }) => ({ countryCode, songs }));
  }

  /** Chronological play log, newest first (UTC timestamps). */
  getRecentPlays(limit = 100): PlayEvent[] {
    return [...this.events].reverse().slice(0, limit);
  }

  getSummary() {
    return {
      totalPlays: this.events.length,
      uniqueSongs: this.aggregates.size,
    };
  }

  toDashboardPayload() {
    const summary = this.getSummary();
    return {
      generatedAt: nowUtcIso(),
      totalPlays: summary.totalPlays,
      uniqueSongs: summary.uniqueSongs,
      popularSongs: this.getPopularSongs(50),
      recentPlays: this.getRecentPlays(100),
    };
  }

  toLandingPayload() {
    const summary = this.getSummary();
    return {
      generatedAt: nowUtcIso(),
      totalPlays: summary.totalPlays,
      uniqueSongs: summary.uniqueSongs,
      topSongs: this.getPopularSongs(50),
      topArtists: this.getTopArtists(50),
      bestSongsByCountry: this.getBestSongsByCountry({
        countries: 16,
        songsPerCountry: 5,
      }),
    };
  }

  private load(): void {
    try {
      if (!existsSync(this.dataPath)) return;
      const raw = readFileSync(this.dataPath, 'utf8');
      const parsed = JSON.parse(raw) as PlayLogFile;
      if (parsed.version !== 1 && parsed.version !== 2) return;
      this.events = (Array.isArray(parsed.events) ? parsed.events : []).map((event) => ({
        ...event,
        countryCode: normalizeCountry(
          (event as PlayEvent).countryCode ?? UNKNOWN_COUNTRY,
        ),
      }));
      this.aggregates = new Map(Object.entries(parsed.aggregates ?? {}));
    } catch (error) {
      console.error('[play-log] failed to load', error);
    }
  }

  private scheduleSave(): void {
    if (this.saveTimer) return;
    this.saveTimer = setTimeout(() => {
      this.saveTimer = null;
      this.save();
    }, 250);
  }

  private save(): void {
    try {
      mkdirSync(dirname(this.dataPath), { recursive: true });
      const payload: PlayLogFile = {
        version: 2,
        events: this.events,
        aggregates: Object.fromEntries(this.aggregates),
      };
      writeFileSync(this.dataPath, JSON.stringify(payload, null, 2), 'utf8');
    } catch (error) {
      console.error('[play-log] failed to save', error);
    }
  }
}
