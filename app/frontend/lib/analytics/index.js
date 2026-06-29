// Analytics facade — a thin, consent-gated, provider-agnostic seam. Nothing is
// dispatched until (a) the user has granted consent and (b) a provider is
// registered via `registerProvider`. Until then calls are safe no-ops, so call
// sites never need to guard. All page paths are run through `maskPath` so record
// ids never reach a third party. Mirrors the adv-os analytics discipline.
import { maskPath } from './maskPath'

export { maskPath } from './maskPath'
export { EVENTS, META_EVENTS } from './events'

let provider = null
let consent = false

// Buffer events fired before consent/provider are ready so we don't lose the
// session-start page view. Bounded so a misconfiguration can't grow unbounded.
const MAX_BUFFER = 50
let buffer = []

function dispatch(type, payload) {
  if (!consent || !provider) {
    if (buffer.length < MAX_BUFFER) buffer.push({ type, payload })
    return
  }
  try {
    provider[type]?.(payload)
  } catch {
    // Analytics must never break the app.
  }
}

function flush() {
  if (!consent || !provider) return
  const pending = buffer
  buffer = []
  pending.forEach(({ type, payload }) => dispatch(type, payload))
}

// Register the concrete sink (e.g. a PostHog/Segment adapter). Shape:
// { page({path,...}), track({event,props}), identify({id,traits}), reset() }.
export function registerProvider(impl) {
  provider = impl
  flush()
}

export function setConsent(granted) {
  consent = Boolean(granted)
  if (consent) flush()
  else buffer = []
}

export function hasConsent() {
  return consent
}

export function page(pathname, props = {}) {
  dispatch('page', { path: maskPath(pathname), ...props })
}

export function track(event, props = {}) {
  dispatch('track', { event, props })
}

export function identify(id, traits = {}) {
  dispatch('identify', { id, traits })
}

export function reset() {
  buffer = []
  try {
    provider?.reset?.()
  } catch {
    // ignore
  }
}

export default { page, track, identify, reset, registerProvider, setConsent, hasConsent, maskPath }
