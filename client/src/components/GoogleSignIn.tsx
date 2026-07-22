import { useEffect, useRef } from 'react';
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
      };
    };
  }
}

function parseCredential(credential: string): AuthUser {
  const payload = JSON.parse(atob(credential.split('.')[1]!.replace(/-/g, '+').replace(/_/g, '/')));
  return {
    id: String(payload.sub),
    displayName: String(payload.name || payload.email || 'Google User'),
    email: String(payload.email || ''),
    isGuest: false,
  };
}

export function GoogleSignInButton({
  onSignedIn,
  label = 'Sign in with Google',
}: {
  onSignedIn?: (user: AuthUser) => void;
  label?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const setUser = useAuthStore((s) => s.setUser);

  useEffect(() => {
    if (!GOOGLE_CLIENT_ID || !ref.current) return;

    const tryInit = () => {
      if (!window.google?.accounts?.id || !ref.current) return false;
      window.google.accounts.id.initialize({
        client_id: GOOGLE_CLIENT_ID,
        callback: (response: { credential: string }) => {
          const user = parseCredential(response.credential);
          setUser(user);
          onSignedIn?.(user);
        },
      });
      ref.current.innerHTML = '';
      window.google.accounts.id.renderButton(ref.current, {
        theme: 'outline',
        size: 'large',
        text: 'signin_with',
        width: 280,
      });
      return true;
    };

    if (tryInit()) return;
    const timer = setInterval(() => {
      if (tryInit()) clearInterval(timer);
    }, 200);
    return () => clearInterval(timer);
  }, [onSignedIn, setUser]);

  if (!GOOGLE_CLIENT_ID) {
    return (
      <p className="muted small">
        Google Sign-In needs <code>VITE_GOOGLE_CLIENT_ID</code> (Web OAuth client).
      </p>
    );
  }

  return (
    <div className="google-btn-wrap">
      <div ref={ref} aria-label={label} />
    </div>
  );
}
