import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { isJoinCode, resolveJoinCode } from '../api/relay';
import { GoogleSignInButton } from '../components/GoogleSignIn';
import { useAuthStore } from '../store/auth';
import { useConnectStore } from '../store/connectSession';

export function ConnectJoin() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const deviceId = useAuthStore((s) => s.deviceId);
  const setUser = useAuthStore((s) => s.setUser);
  const displayName = useConnectStore((s) => s.displayName);
  const setDisplayName = useConnectStore((s) => s.setDisplayName);
  const join = useConnectStore((s) => s.join);
  const busy = useConnectStore((s) => s.busy);
  const error = useConnectStore((s) => s.error);
  const clearError = useConnectStore((s) => s.clearError);
  const saved = useConnectStore((s) => s.savedConnections);
  const removeSaved = useConnectStore((s) => s.removeSaved);

  const [mode, setMode] = useState<'code' | 'recent'>('code');
  const [code, setCode] = useState('');
  const [localError, setLocalError] = useState<string | null>(null);

  const invite = useMemo(() => {
    const session = params.get('session') || params.get('sessionId');
    const server = params.get('server') || params.get('serverUrl');
    const inviteCode = params.get('code');
    return { session, server, inviteCode };
  }, [params]);

  useEffect(() => {
    if (invite.inviteCode && isJoinCode(invite.inviteCode)) {
      setCode(invite.inviteCode.toUpperCase());
      setMode('code');
    }
  }, [invite.inviteCode]);

  const doJoin = async (sessionId: string, serverUrl: string) => {
    clearError();
    setLocalError(null);
    const name = displayName.trim();
    if (!name) {
      setLocalError('Enter your name first');
      return;
    }
    try {
      await join({ sessionId, serverUrl, displayName: name, deviceId });
      navigate('/connect/session');
    } catch (err) {
      setLocalError(err instanceof Error ? err.message : String(err));
    }
  };

  const joinWithCode = async () => {
    const normalized = code.trim().toUpperCase();
    if (!isJoinCode(normalized)) {
      setLocalError('Enter a 6-character code (A–Z, 0–9)');
      return;
    }
    try {
      const resolved = await resolveJoinCode(normalized);
      await doJoin(resolved.sessionId, resolved.serverUrl);
    } catch (err) {
      setLocalError(err instanceof Error ? err.message : String(err));
    }
  };

  useEffect(() => {
    if (!invite.session || !invite.server) return;
    // Prefill only; user confirms with name + join.
  }, [invite.session, invite.server]);

  return (
    <div className="page">
      <header className="topbar">
        <Link to="/" className="back">
          ←
        </Link>
        <h1>Connect to Host</h1>
      </header>

      <section className="stack">
        <label>
          Your name
          <input
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            disabled={busy}
            placeholder="Shown when you request a song"
          />
        </label>

        <div className="segmented">
          <button
            type="button"
            className={mode === 'code' ? 'active' : ''}
            onClick={() => setMode('code')}
          >
            Enter code
          </button>
          <button
            type="button"
            className={mode === 'recent' ? 'active' : ''}
            onClick={() => setMode('recent')}
          >
            Recent
          </button>
        </div>

        {invite.session && invite.server && (
          <div className="row-card">
            <div>
              <strong>Session invite ready</strong>
              <div className="muted small mono">{invite.session}</div>
            </div>
            <button
              type="button"
              className="btn primary small"
              disabled={busy}
              onClick={() => void doJoin(invite.session!, invite.server!)}
            >
              Join session
            </button>
          </div>
        )}

        {mode === 'code' ? (
          <>
            <p className="muted">Enter the 6-character code shown on the host.</p>
            <input
              className="code-input"
              value={code}
              maxLength={6}
              disabled={busy}
              onChange={(e) =>
                setCode(e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ''))
              }
              onKeyDown={(e) => e.key === 'Enter' && void joinWithCode()}
              placeholder="ABC123"
            />
            <button
              type="button"
              className="btn primary"
              disabled={busy}
              onClick={() => void joinWithCode()}
            >
              Join with code
            </button>
          </>
        ) : (
          <div className="list">
            {saved.length === 0 && (
              <p className="muted center">No recent sessions yet</p>
            )}
            {saved.map((c) => (
              <div key={`${c.serverUrl}|${c.sessionId}`} className="row-card">
                <button
                  type="button"
                  className="linkish"
                  disabled={busy}
                  onClick={() => void doJoin(c.sessionId, c.serverUrl)}
                >
                  <strong>{c.sessionName}</strong>
                  <div className="muted small mono">{c.sessionId.slice(0, 8)}…</div>
                </button>
                <button
                  type="button"
                  className="btn ghost small"
                  onClick={() => removeSaved(c.sessionId, c.serverUrl)}
                >
                  Remove
                </button>
              </div>
            ))}
          </div>
        )}

        <GoogleSignInButton
          onSignedIn={(user) => {
            setUser(user);
            if (!displayName.trim()) setDisplayName(user.displayName);
          }}
        />

        {(localError || error) && <p className="error">{localError || error}</p>}
      </section>
    </div>
  );
}
