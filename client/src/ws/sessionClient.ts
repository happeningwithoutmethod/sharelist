type Handler = (message: Record<string, unknown>) => void;

export class SessionClient {
  private socket: WebSocket | null = null;
  private handlers = new Set<Handler>();
  private pingTimer: ReturnType<typeof setInterval> | null = null;
  private onDisconnect: (() => void) | null = null;
  private closing = false;

  constructor(private serverUrl: string) {}

  get connected(): boolean {
    return this.socket?.readyState === WebSocket.OPEN;
  }

  addHandler(handler: Handler): void {
    this.handlers.add(handler);
  }

  removeHandler(handler: Handler): void {
    this.handlers.delete(handler);
  }

  setDisconnectListener(listener: (() => void) | null): void {
    this.onDisconnect = listener;
  }

  async connect(): Promise<void> {
    await this.disconnect();
    this.closing = false;
    const base = this.serverUrl.replace(/\/+$/, '');
    const url = `${base}/session`;

    await new Promise<void>((resolve, reject) => {
      const ws = new WebSocket(url);
      const timer = setTimeout(() => {
        ws.close();
        reject(new Error(`Timed out connecting to ${url}`));
      }, 10_000);

      ws.onopen = () => {
        clearTimeout(timer);
        this.socket = ws;
        this.startPing();
        resolve();
      };
      ws.onerror = () => {
        clearTimeout(timer);
        reject(new Error(`Could not connect to ${url}`));
      };
      ws.onmessage = (event) => {
        try {
          const message = JSON.parse(String(event.data)) as Record<string, unknown>;
          for (const handler of [...this.handlers]) handler(message);
        } catch {
          // ignore malformed frames
        }
      };
      ws.onclose = () => {
        this.stopPing();
        this.socket = null;
        if (!this.closing) this.onDisconnect?.();
      };
    });
  }

  send(message: Record<string, unknown>): void {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return;
    this.socket.send(JSON.stringify({ ...message, ts: Date.now() }));
  }

  async disconnect(): Promise<void> {
    this.closing = true;
    this.stopPing();
    const socket = this.socket;
    this.socket = null;
    if (socket && socket.readyState === WebSocket.OPEN) {
      socket.close();
    }
  }

  private startPing(): void {
    this.stopPing();
    this.pingTimer = setInterval(() => {
      this.send({ type: 'ping' });
    }, 15_000);
  }

  private stopPing(): void {
    if (this.pingTimer) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
  }
}
