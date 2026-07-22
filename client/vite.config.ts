import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  base: '/web/',
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'https://sharelist.servehttp.com',
        changeOrigin: true,
        secure: true,
      },
      '/health': {
        target: 'https://sharelist.servehttp.com',
        changeOrigin: true,
        secure: true,
      },
      '/privacy': {
        target: 'https://sharelist.servehttp.com',
        changeOrigin: true,
        secure: true,
      },
    },
  },
});
