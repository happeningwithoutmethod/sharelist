import { Navigate, Route, Routes } from 'react-router-dom';
import { ConnectJoin } from './pages/ConnectJoin';
import { ConnectShell } from './pages/ConnectShell';
import { HostShell } from './pages/HostShell';
import { HostStart } from './pages/HostStart';
import { ModePicker } from './pages/ModePicker';
import { PrivacyGate } from './pages/PrivacyGate';

export default function App() {
  return (
    <Routes>
      <Route element={<PrivacyGate />}>
        <Route path="/" element={<ModePicker />} />
        <Route path="/host" element={<HostStart />} />
        <Route path="/host/session" element={<HostShell />} />
        <Route path="/connect" element={<ConnectJoin />} />
        <Route path="/connect/session" element={<ConnectShell />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
