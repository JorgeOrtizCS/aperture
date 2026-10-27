import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// The Web API (Aperture WebAPI, `dotnet run`) listens on http://localhost:5080.
// Proxying /api keeps the browser on one origin, so the API needs no CORS setup,
// and the API still sees the client's real (loopback) IP for its session binding.
const apiTarget = process.env.APERTURE_API_URL ?? 'http://localhost:5080'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': { target: apiTarget, changeOrigin: false },
    },
  },
})
