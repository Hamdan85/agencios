import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Toaster } from 'sonner'
import App from '@/App'
import { bootAnalytics } from '@/lib/analytics/boot'
import './application.css'

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

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <Toaster richColors position="top-right" toastOptions={{ style: { fontFamily: 'var(--font-sans)' } }} />
      <App />
    </QueryClientProvider>
  </StrictMode>,
)
