import type { IncomingMessage, ServerResponse } from 'node:http';

const SEARCH_ENDPOINT = 'https://www.googleapis.com/youtube/v3/search';
const DEFAULT_MAX_RESULTS = 20;

export interface MusicTrackDto {
  id: string;
  title: string;
  artist: string;
  artworkUrl?: string;
  sourceUrl: string;
  provider: string;
}

function youtubeApiKey(): string {
  const key = process.env.YOUTUBE_API_KEY?.trim() ?? '';
  if (!key) {
    throw new Error(
      'YOUTUBE_API_KEY is not set. Create a Google Cloud API key with YouTube Data API v3 enabled.',
    );
  }
  return key;
}

function sendJson(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify(body));
}

function sendCorsPreflight(res: ServerResponse): void {
  res.writeHead(204, {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400',
  });
  res.end();
}

interface SearchListItem {
  id?: { videoId?: string };
  snippet?: {
    title?: string;
    channelTitle?: string;
    thumbnails?: {
      high?: { url?: string };
      medium?: { url?: string };
      default?: { url?: string };
    };
  };
}

interface SearchListResponse {
  items?: SearchListItem[];
  error?: { message?: string; code?: number };
}

/**
 * YouTube Data API v3 `search.list` (type=video).
 * Quota: search.list is billed from the Search Queries bucket (~100 calls/day default).
 */
export async function searchTracks(query: string): Promise<MusicTrackDto[]> {
  const trimmed = query.trim();
  if (!trimmed) return [];

  const url = new URL(SEARCH_ENDPOINT);
  url.searchParams.set('part', 'snippet');
  url.searchParams.set('type', 'video');
  url.searchParams.set('maxResults', String(DEFAULT_MAX_RESULTS));
  url.searchParams.set('safeSearch', 'moderate');
  url.searchParams.set('q', trimmed);
  url.searchParams.set('key', youtubeApiKey());

  const response = await fetch(url);
  const data = (await response.json()) as SearchListResponse;

  if (!response.ok) {
    const detail = data.error?.message ?? `HTTP ${response.status}`;
    throw new Error(`YouTube Data API search failed: ${detail}`);
  }

  const tracks: MusicTrackDto[] = [];
  for (const item of data.items ?? []) {
    const videoId = item.id?.videoId?.trim() ?? '';
    if (!videoId) continue;
    const title = item.snippet?.title?.trim() || 'Unknown title';
    const artist = item.snippet?.channelTitle?.trim() || 'Unknown artist';
    const thumbs = item.snippet?.thumbnails;
    const artworkUrl =
      thumbs?.high?.url ?? thumbs?.medium?.url ?? thumbs?.default?.url;

    tracks.push({
      id: videoId,
      title,
      artist,
      artworkUrl,
      sourceUrl: `https://www.youtube.com/watch?v=${videoId}`,
      provider: 'youtube_music',
    });
  }
  return tracks;
}

export async function handleMusicApi(
  req: IncomingMessage,
  res: ServerResponse,
  url: URL,
): Promise<boolean> {
  if (!url.pathname.startsWith('/api/music')) {
    return false;
  }

  if (req.method === 'OPTIONS') {
    sendCorsPreflight(res);
    return true;
  }

  try {
    if (url.pathname === '/api/music/search' && req.method === 'GET') {
      const query = url.searchParams.get('q')?.trim() ?? '';
      if (!query) {
        sendJson(res, 400, { error: 'Missing q parameter' });
        return true;
      }
      const tracks = await searchTracks(query);
      sendJson(res, 200, { tracks });
      return true;
    }

    sendJson(res, 404, { error: 'Not found' });
    return true;
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Music API error';
    const status = message.includes('YOUTUBE_API_KEY') ? 503 : 500;
    sendJson(res, status, { error: message });
    return true;
  }
}
