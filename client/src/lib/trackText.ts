import { decodeHtmlEntities } from './htmlEntities';
import type { Track } from '../protocol/types';

/** Prefer decoded title/artist for display (covers older playlist entries). */
export function trackTitle(track: Track): string {
  return decodeHtmlEntities(track.title);
}

export function trackArtist(track: Track): string {
  return decodeHtmlEntities(track.artist);
}
