// Frontend error monitoring. The browser DSN is public (safe to ship in the
// bundle) but is injected per-environment via `window.__AGENCIOS_SENTRY` from
// the SPA HTML shell (ENV → server), mirroring how analytics config is exposed.
// Sentry stays inert when no DSN is configured (e.g. local dev without the key).
import * as Sentry from '@sentry/react'

let initialized = false

export function initSentry() {
  if (initialized || typeof window === 'undefined') return
  const cfg = window.__AGENCIOS_SENTRY || {}
  if (!cfg.dsn) return

  initialized = true

  Sentry.init({
    dsn: cfg.dsn,
    environment: cfg.environment || 'production',
    release: cfg.release || undefined,
    integrations: [
      Sentry.browserTracingIntegration(),
      Sentry.replayIntegration(),
    ],
    // Performance tracing — sample lightly in production.
    tracesSampleRate: cfg.tracesSampleRate ?? 0.1,
    // Session Replay — none by default, all sessions with an error.
    replaysSessionSampleRate: cfg.replaysSessionSampleRate ?? 0,
    replaysOnErrorSampleRate: cfg.replaysOnErrorSampleRate ?? 1.0,
    sendDefaultPii: true,
  })
}

export { Sentry }
