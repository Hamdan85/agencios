import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'
import path from 'path'

const appHost = process.env.APP_HOST ?? ''
const behindHttpsProxy = appHost.startsWith('https://')

let appHostUrl: URL | null = null
if (appHost) {
  try {
    appHostUrl = new URL(appHost)
  } catch {
    appHostUrl = null
  }
}

export default defineConfig({
  clearScreen: false,
  plugins: [
    tailwindcss(),
    RubyPlugin(),
    react(),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'app/frontend'),
    },
  },
  server: {
    host: true,
    // Allow the dev server to answer requests proxied in under the external
    // host (e.g. an ngrok tunnel) in addition to the localhost defaults
    // (Vite blocks unknown hosts).
    allowedHosts: appHostUrl ? [appHostUrl.hostname, '.ngrok-free.app'] : undefined,
    // Behind an HTTPS tunnel (e.g. ngrok), modules are served fine through
    // Rails' /vite-dev/ proxy, but the HMR websocket can't be: a single free
    // ngrok tunnel forwards only Rails (:3000), the Vite dev-server port isn't
    // exposed, and Rails' rack-proxy doesn't forward websocket upgrades. Leaving
    // HMR on just makes the client spin on a dead socket, so disable it here —
    // edit then refresh. (Local, non-tunnel dev keeps HMR; it connects straight
    // to the Vite port.) Pre-bundling (optimizeDeps below) keeps refreshes from
    // needing the reload HMR would otherwise trigger.
    //
    // Note: we deliberately do NOT set `server.origin` — it would bake the
    // absolute tunnel URL into every module and break opening the app from any
    // other origin (e.g. http://localhost:3000); relative URLs work on both.
    ...(behindHttpsProxy && appHostUrl ? { hmr: false as const } : {}),
  },
  // Pre-bundle deps by scanning ALL frontend sources, not just those statically
  // reachable from the entrypoint. Without this, packages used only by
  // lazy-loaded routes (radix-ui, class-variance-authority, …) are discovered
  // on first navigation, triggering an on-the-fly re-optimize that returns 504
  // for in-flight module requests and breaks the dynamic import.
  optimizeDeps: {
    // Paths are relative to Vite's root, which vite-plugin-ruby sets to the
    // sourceCodeDir (app/frontend) — so glob from there, not the repo root.
    entries: ['**/*.{js,jsx,ts,tsx}'],
  },
})
