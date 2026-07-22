import { useCallback, useEffect, useState } from 'react';
import { GOOGLE_CLIENT_ID } from '../config';
import { useAuthStore, type AuthUser } from '../store/auth';

declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize: (cfg: Record<string, unknown>) => void;
          renderButton: (el: HTMLElement, cfg: Record<string, unknown>) => void;
          prompt: () => void;
        };
        oauth2: {
          initTokenClient: (cfg: {
            client_id: string;
            scope: string;
            callback: (response: {
              access_token?: string;
              error?: string;
              error_description?: string;
            }) => void;
          }) => { requestAccessToken: (opts?: { prompt?: string }) => void };
        };
      };
    };
  }
}

function loadGis(): Promise<void> {
  if (window.google?.accounts?.oauth2) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const tick = () => {
      if (window.google?.accounts?.oauth2) {
        resolve();
        return;
      }
      if (Date.now() - started > 10_000) {
        reject(new Error('Google Sign-In script did not load'));
        return;
      }
      requestAnimationFrame(tick);
    };
    tick();
  });
}

async function fetchGoogleUser(accessToken: string): Promise<AuthUser> {
  const res = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new Error('Could not load Google profile');
  const profile = (await res.json()) as {
    sub?: string;
    name?: string;
    email?: string;
  };
  return {
    id: String(profile.sub ?? ''),
    displayName: String(profile.name || profile.email || 'Google User'),
    email: String(profile.email || ''),
    isGuest: false,
  };
}

export function GoogleSignInButton({
  onSignedIn,
  label = 'Sign in with Google',
  disabled = false,
}: {
  onSignedIn?: (user: AuthUser) => void;
  label?: string;
  disabled?: boolean;
}) {
  const setUser = useAuthStore((s) => s.setUser);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (!GOOGLE_CLIENT_ID) return;
    void loadGis()
      .then(() => setReady(true))
      .catch((err) =>
        setError(err instanceof Error ? err.message : String(err)),
      );
  }, []);

  const signIn = useCallback(() => {
    if (!GOOGLE_CLIENT_ID || !window.google?.accounts?.oauth2 || busy) return;
    setError(null);
    setBusy(true);
    const client = window.google.accounts.oauth2.initTokenClient({
      client_id: GOOGLE_CLIENT_ID,
      scope: 'openid email profile',
      callback: (response) => {
        void (async () => {
          try {
            if (response.error || !response.access_token) {
              throw new Error(
                response.error_description ||
                  response.error ||
                  'Google sign-in was cancelled',
              );
            }
            const user = await fetchGoogleUser(response.access_token);
            if (!user.id) throw new Error('Google profile missing user id');
            setUser(user);
            onSignedIn?.(user);
          } catch (err) {
            setError(err instanceof Error ? err.message : String(err));
          } finally {
            setBusy(false);
          }
        })();
      },
    });
    client.requestAccessToken({ prompt: '' });
  }, [busy, onSignedIn, setUser]);

  if (!GOOGLE_CLIENT_ID) {
    return (
      <p className="muted small">
        Google Sign-In needs <code>VITE_GOOGLE_CLIENT_ID</code> in{' '}
        <code>client/.env</code>, then restart <code>npm run dev</code>.
      </p>
    );
  }

  return (
    <div className="google-btn-wrap">
      <button
        type="button"
        className="btn ghost google-signin-btn"
        disabled={disabled || busy || !ready}
        onClick={signIn}
      >
        <span className="google-g" aria-hidden>
          G
        </span>
        {busy ? 'Signing in…' : ready ? label : 'Loading Google…'}
      </button>
      {error && (
        <p className="error small">
          {error}
          {error.toLowerCase().includes('origin') ||
          error.toLowerCase().includes('load')
            ? ` Add ${window.location.origin} under Authorized JavaScript origins.`
            : null}
        </p>
      )}
    </div>
  );
}
