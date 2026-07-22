import { QRCodeSVG } from 'qrcode.react';

export function QrCode({ value, size = 220 }: { value: string; size?: number }) {
  return (
    <div className="qr-box">
      <QRCodeSVG value={value} size={size} level="M" includeMargin />
    </div>
  );
}
