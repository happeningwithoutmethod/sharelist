import { create } from 'zustand';
import { v4 as uuid } from 'uuid';

export interface AuthUser {
  id: string;
  displayName: string;
  email: string;
  isGuest: boolean;
}

const DEVICE_KEY = 'sharelist.deviceId';
const USER_KEY = 'sharelist.authUser';
const PRIVACY_KEY = 'sharelist.privacyAccepted';
const PRIVACY_VERSION = '1';

function loadDeviceId(): string {
  const existing = localStorage.getItem(DEVICE_KEY);
  if (existing) return existing;
  const id = uuid();
  localStorage.setItem(DEVICE_KEY, id);
  return id;
}

function loadUser(): AuthUser | null {
  try {
    const raw = localStorage.getItem(USER_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as AuthUser;
  } catch {
    return null;
  }
}

interface AuthState {
  deviceId: string;
  user: AuthUser | null;
  privacyAccepted: boolean;
  setUser: (user: AuthUser | null) => void;
  setGuest: (displayName?: string) => AuthUser;
  acceptPrivacy: () => void;
}

export const useAuthStore = create<AuthState>((set) => ({
  deviceId: loadDeviceId(),
  user: loadUser(),
  privacyAccepted: localStorage.getItem(PRIVACY_KEY) === PRIVACY_VERSION,
  setUser: (user) => {
    if (user) localStorage.setItem(USER_KEY, JSON.stringify(user));
    else localStorage.removeItem(USER_KEY);
    set({ user });
  },
  setGuest: (displayName = 'Guest Host') => {
    const deviceId = loadDeviceId();
    const user: AuthUser = {
      id: `guest:${deviceId}`,
      displayName,
      email: '',
      isGuest: true,
    };
    localStorage.setItem(USER_KEY, JSON.stringify(user));
    set({ user, deviceId });
    return user;
  },
  acceptPrivacy: () => {
    localStorage.setItem(PRIVACY_KEY, PRIVACY_VERSION);
    set({ privacyAccepted: true });
  },
}));
