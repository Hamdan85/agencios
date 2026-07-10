import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Toaster } from 'sonner'
import App from '@/App'
import i18n from '@/i18n'
import { Button } from '@/components/ui/button'
import { ConfirmProvider } from '@/components/ui/confirm-dialog'
import { ErrorScene } from '@/components/errors/ErrorScene'
import { bootAnalytics } from '@/lib/analytics/boot'
import { initSentry, Sentry } from '@/lib/sentry'
import './application.css'

// Top-level crash screen for render errors that escape the router (the router
// has its own errorElement). Sentry has already captured the exception by the
// time this renders; reloading re-mounts the app from a clean slate.
function AppErrorFallback() {
  return (
    <ErrorScene
      code="500"
      title={i18n.t('errors.crashTitle')}
      description={i18n.t('errors.crashDescription')}
      actions={<Button size="lg" onClick={() => window.location.reload()}>{i18n.t('errors.reload')}</Button>}
    />
  )
}

// Boot error monitoring before anything else so early failures are captured.
initSentry()

// Mark this surface as the SPA and wire the analytics fan-out provider into the
// consent-gated facade. Page views + identify are then driven by AnalyticsBridge.
window.__AGENCIOS_SPA = true
bootAnalytics()

// Capture the install prompt before React mounts — beforeinstallprompt fires
// once early in page load; the InstallPromptBanner picks it up from here.
window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault()
  window.__installPrompt = e
  window.dispatchEvent(new Event('agencios-install-prompt-ready'))
})

// Register the service worker (enables installability + Web Push).
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker
      .register('/service-worker.js')
      .catch((err) => console.warn('Service worker registration failed:', err))
  })
}

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
})

// Expose the query client to the axios layer so the global 402 handler can
// invalidate `/me` (triggering the paywall guard) from outside React.
window.__queryClient = queryClient

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <Toaster richColors closeButton position="top-right" toastOptions={{ style: { fontFamily: 'var(--font-sans)' } }} />
      <ConfirmProvider>
        <Sentry.ErrorBoundary fallback={<AppErrorFallback />}>
          <App />
        </Sentry.ErrorBoundary>
      </ConfirmProvider>
    </QueryClientProvider>
  </StrictMode>,
)
