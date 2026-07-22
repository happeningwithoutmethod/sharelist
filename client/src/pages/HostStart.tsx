import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { checkRelayHealth } from '../api/relay';
import { GoogleSignInButton } from '../components/GoogleSignIn';
import { WS_URL } from '../config';
import { useAuthStore } from '../store/auth';
import { useHostStore } from '../store/hostSession';

export function HostStart() {
  const navigate = useNavigate();
  const user = useAuthStore((s) => s.user);
  const setGuest = useAuthStore((s) => s.setGuest);
  const startSession = useHostStore((s) => s.startSession);
  const reconnectSession = useHostStore((s) => s.reconnectSession);
  const storedSession = useHostStore((s) => s.storedSession);
  const busy = useHostStore((s) => s.busy);
  const error = useHostStore((s) => s.error);
  const clearError = useHostStore((s) => s.clearError);

  const [sessionName, setSessionName] = useState('Share List Session');
  const [serverUrl, setServerUrl] = useState(WS_URL);
  const [relayOnline, setRelayOnline] = useState<boolean | null>(null);
  const [localError, setLocalError] = useState<string | null>(null);

  useEffect(() => {
    void checkRelayHealth(serverUrl).then(setRelayOnline);
  }, [serverUrl]);

  const start = async (asGuest: boolean) => {
    clearError();
    setLocalError(null);
    if (relayOnline === false) {
      setLocalError('Relay server is offline. Wait until it is reachable.');
      return;
    }
    try {
      const hostUser = asGuest
        ? setGuest('Guest Host')
        : user && !user.isGuest
          ? user
          : setGuest('Guest Host');
      await startSession({
        user: hostUser,
        sessionName: sessionName.trim() || 'Share List Session',
        serverUrl: serverUrl.trim() || WS_URL,
      });
      navigate('/host/session');
    } catch (err) {
      setLocalError(err instanceof Error ? err.message : String(err));
    }
  };

  const resume = async () => {
    if (!storedSession) return;
    clearError();
    setLocalError(null);
    try {
      const hostUser =
        user && user.id === storedSession.hostGoogleSub
          ? user
          : storedSession.hostGoogleSub.startsWith('guest:')
            ? setGuest('Guest Host')
            : null;
      if (!hostUser) {
        setLocalError('Sign in with the same Google account to resume.');
        return;
      }
      await reconnectSession(hostUser);
      navigate('/host/session');
    } catch (err) {
      setLocalError(err instanceof Error ? err.message : String(err));
    }
  };

  return (
    <div className="page">
      <header className="topbar">
        <Link to="/" className="back">
          ←
        </Link>
        <h1>Host Mode</h1>
      </header>

      <section className="stack">
        <h2>Start a session</h2>
        <p className="muted">
          You can start immediately without Google. Optional Google sign-in is
          only needed later for Premium YouTube Music.
        </p>

        <label>
          Session name
          <input
            value={sessionName}
            onChange={(e) => setSessionName(e.target.value)}
            disabled={busy}
          />
        </label>

        <label>
          Relay server URL
          <input
            value={serverUrl}
            onChange={(e) => setServerUrl(e.target.value)}
            disabled={busy}
          />
        </label>
        <p className="muted small">Defaults to {WS_URL}</p>

        <div className={`status-row ${relayOnline ? 'ok' : relayOnline === false ? 'bad' : ''}`}>
          <span>
            {relayOnline == null
              ? 'Checking relay…'
              : relayOnline
                ? 'Relay server online'
                : 'Relay server offline'}
          </span>
          <button
            type="button"
            className="icon-btn"
            onClick={() => void checkRelayHealth(serverUrl).then(setRelayOnline)}
          >
            ↻
          </button>
        </div>

        {storedSession && (
          <button type="button" className="btn ghost" disabled={busy} onClick={() => void resume()}>
            Resume previous session
          </button>
        )}

        <button
          type="button"
          className="btn primary"
          disabled={busy}
          onClick={() => void start(true)}
        >
          Start without Google
        </button>

        <GoogleSignInButton
          disabled={busy}
          onSignedIn={() => {
            /* user stored; they can start as Google below */
          }}
        />

        {user && !user.isGuest && (
          <button
            type="button"
            className="btn ghost"
            disabled={busy}
            onClick={() => void start(false)}
          >
            Start as {user.displayName}
          </button>
        )}

        {(localError || error) && (
          <p className="error">{localError || error}</p>
        )}
      </section>
    </div>
  );
}
