import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    // Web Bluetooth requires a secure context. localhost counts as secure, so
    // `npm run dev` works as-is; if you serve to a phone on the LAN you need
    // HTTPS or an SSH tunnel.
    host: true,
    port: 5173,
  },
  build: {
    target: 'es2022',
    sourcemap: true,
  },
});
