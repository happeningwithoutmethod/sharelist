import type { ReactNode } from 'react';
import { decodeHtmlEntities } from '../lib/htmlEntities';
import type { Track } from '../protocol/types';

export function TrackRow({
  track,
  meta,
  actions,
  active,
}: {
  track: Track;
  meta?: string;
  actions?: ReactNode;
  active?: boolean;
}) {
  const title = decodeHtmlEntities(track.title);
  const artist = decodeHtmlEntities(track.artist);
  return (
    <div className={`track-row ${active ? 'active' : ''}`}>
      {track.artworkUrl ? (
        <img src={track.artworkUrl} alt="" className="art" />
      ) : (
        <div className="art placeholder" />
      )}
      <div className="meta">
        <div className="title">{title}</div>
        <div className="artist">{artist}</div>
        {meta && <div className="sub">{meta}</div>}
      </div>
      {actions && <div className="actions">{actions}</div>}
    </div>
  );
}

export function formatMs(ms: number): string {
  if (!Number.isFinite(ms) || ms < 0) return '0:00';
  const total = Math.floor(ms / 1000);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}
