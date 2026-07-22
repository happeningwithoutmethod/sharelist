import { Link } from 'react-router-dom';
import { API_ORIGIN, WS_URL } from '../config';

export function ModePicker() {
  return (
    <div className="page hero-page">
      <div className="hero-bg" aria-hidden />
      <header className="hero">
        <p className="eyebrow">Collaborative playlists</p>
        <h1 className="brand">Share List</h1>
        <p className="lede">
          Host the music or connect with a code — one session, shared taste.
        </p>
        <div className="cta-row">
          <Link className="btn primary" to="/host">
            Host mode
          </Link>
          <Link className="btn ghost" to="/connect">
            Connect
          </Link>
        </div>
        <p className="muted small relay-hint">Relay · {WS_URL.replace(/^wss?:\/\//, '')}</p>
        <p className="muted small">
          <a href={`${API_ORIGIN}/privacy`} target="_blank" rel="noreferrer">
            Privacy
          </a>
        </p>
      </header>
    </div>
  );
}
