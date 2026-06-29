// One-time analytics boot shared by both surfaces (the React SPA entrypoint and
// the vanilla marketing entrypoint). It wires the fan-out provider into the
// facade and keeps the facade's consent flag in sync with the cookie banner.
//
// Load order: the cookie-consent partial renders at the end of <body> with a
// plain inline <script>, so it runs BEFORE these deferred ES modules. By the
// time bootAnalytics() runs, `window.__AGENCIOS_CONSENT` already reflects any
// stored choice; later changes arrive via the `agencios:consent` CustomEvent.
import { registerProvider, setConsent } from './index'
import { createProvider } from './provider'

let booted = false

export function bootAnalytics() {
  if (booted || typeof window === 'undefined') return
  booted = true

  registerProvider(createProvider())

  const sync = () => setConsent(window.__AGENCIOS_CONSENT === 'granted')
  sync() // pick up a stored choice made before this module loaded
  window.addEventListener('agencios:consent', sync)
}

export default bootAnalytics
