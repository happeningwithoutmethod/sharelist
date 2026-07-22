import { Outlet } from 'react-router-dom';
import { API_ORIGIN } from '../config';
import { useAuthStore } from '../store/auth';

export function PrivacyGate() {
  const accepted = useAuthStore((s) => s.privacyAccepted);
  const acceptPrivacy = useAuthStore((s) => s.acceptPrivacy);

  if (accepted) return <Outlet />;

  return (
    <div className="page narrow">
      <h1 className="brand">Share List</h1>
      <p>
        Before you continue, please review the privacy policy. This app uses the
        YouTube API Services and Google Sign-In when you choose to sign in.
      </p>
      <p>
        <a href={`${API_ORIGIN}/privacy`} target="_blank" rel="noreferrer">
          Open privacy policy
        </a>
      </p>
      <button type="button" className="btn primary" onClick={acceptPrivacy}>
        I agree — continue
      </button>
    </div>
  );
}
