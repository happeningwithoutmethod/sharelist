import type { Track } from '../protocol/types';
import { decodeHtmlEntities } from './htmlEntities';

export const LST_FORMAT = 'share-list.lst';
export const LST_VERSION = 1;

export interface LstPlaylistFile {
  format: typeof LST_FORMAT;
  version: number;
  name: string;
  savedAt: string;
  tracks: Track[];
}

export function playlistToShareText(
  sessionName: string,
  playlist: Track[],
): string {
  const lines = [`${sessionName}`, ''];
  playlist.forEach((track, i) => {
    lines.push(
      `${i + 1}. ${decodeHtmlEntities(track.title)} — ${decodeHtmlEntities(track.artist)}`,
    );
  });
  return lines.join('\n').trimEnd();
}

export function serializeLst(input: {
  name: string;
  tracks: Track[];
  savedAt?: Date;
}): string {
  const body: LstPlaylistFile = {
    format: LST_FORMAT,
    version: LST_VERSION,
    name: input.name.trim() || 'Playlist',
    savedAt: (input.savedAt ?? new Date()).toISOString(),
    tracks: input.tracks.map((t) => ({
      id: t.id,
      title: decodeHtmlEntities(t.title),
      artist: decodeHtmlEntities(t.artist),
      artworkUrl: t.artworkUrl ?? null,
      sourceUrl: t.sourceUrl,
      provider: t.provider,
    })),
  };
  return `${JSON.stringify(body, null, 2)}\n`;
}

export function parseLst(raw: string): LstPlaylistFile {
  let data: unknown;
  try {
    data = JSON.parse(raw);
  } catch {
    throw new Error('Not a valid .lst file (invalid JSON)');
  }
  if (!data || typeof data !== 'object') {
    throw new Error('Not a valid .lst file');
  }
  const obj = data as Record<string, unknown>;
  if (obj.format !== LST_FORMAT) {
    throw new Error('Not a Share List .lst file');
  }
  if (!Array.isArray(obj.tracks)) {
    throw new Error('.lst file has no tracks');
  }
  const tracks: Track[] = [];
  for (const item of obj.tracks) {
    if (!item || typeof item !== 'object') continue;
    const t = item as Record<string, unknown>;
    const id = String(t.id ?? '');
    const title = String(t.title ?? '');
    const artist = String(t.artist ?? '');
    const sourceUrl = String(t.sourceUrl ?? '');
    const provider = String(t.provider ?? 'youtube');
    if (!id || !title || !sourceUrl) continue;
    tracks.push({
      id,
      title,
      artist,
      sourceUrl,
      provider,
      artworkUrl: t.artworkUrl == null ? null : String(t.artworkUrl),
    });
  }
  if (tracks.length === 0) {
    throw new Error('.lst file contains no usable tracks');
  }
  return {
    format: LST_FORMAT,
    version: Number(obj.version ?? 1),
    name: String(obj.name ?? 'Playlist'),
    savedAt: String(obj.savedAt ?? new Date().toISOString()),
    tracks,
  };
}

export function downloadLst(filename: string, contents: string): void {
  const blob = new Blob([contents], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename.endsWith('.lst') ? filename : `${filename}.lst`;
  a.click();
  URL.revokeObjectURL(url);
}

export function sanitizeLstFilename(name: string): string {
  const base = name
    .trim()
    .replace(/[<>:"/\\|?*\u0000-\u001f]/g, '_')
    .replace(/\s+/g, ' ')
    .slice(0, 80);
  return `${base || 'playlist'}.lst`;
}
