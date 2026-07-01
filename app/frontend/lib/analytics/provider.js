// The concrete sink behind the analytics facade — a fan-out provider that
// pushes every call to all three configured destinations at once:
//
//   • Google Tag Manager  — via `window.dataLayer` (GTM routes to GA4 / any tag)
//   • PostHog             — via `window.posthog` (product analytics + replay)
//   • Meta Pixel          — via `window.fbq` (Meta Ads conversions)
//
// The globals are created (and consent-gated) by the cookie-consent partial.
// Until a destination is loaded its global is absent and that branch is a
// no-op, so one `analytics.track(...)` call safely reaches whatever is enabled.
// Paths are already masked by the facade before they get here.
import { META_EVENTS, SERVER_OWNED } from './events'

function gtmPush(obj) {
  if (typeof window === 'undefined') return
  window.dataLayer = window.dataLayer || []
  window.dataLayer.push(obj)
}

// Build the fan-out provider. Shape matches what `registerProvider` expects:
// { page, track, identify, reset }.
export function createProvider() {
  return {
    page({ path, title }) {
      gtmPush({ event: 'page_view', page_path: path, page_title: title || (typeof document !== 'undefined' ? document.title : undefined) })
      window.posthog?.capture?.('$pageview', { $current_url: path })
      window.fbq?.('track', 'PageView')
    },

    track({ event, props }) {
      const payload = props || {}
      gtmPush({ event, ...payload })
      // Server-owned events are captured in PostHog by the backend (with the same
      // distinct_id), so skip the PostHog branch here to avoid double-counting —
      // but still send them to GTM (above) and the Meta Pixel (below).
      if (!SERVER_OWNED.has(event)) window.posthog?.capture?.(event, payload)

      if (window.fbq) {
        const standard = META_EVENTS[event]
        if (standard) window.fbq('track', standard, payload)
        else window.fbq('trackCustom', event, payload)
      }
    },

    identify({ id, traits }) {
      if (!id) return
      gtmPush({ event: 'identify', user_id: id })
      window.posthog?.identify?.(id, traits || {})
    },

    reset() {
      gtmPush({ event: 'logout' })
      window.posthog?.reset?.()
    },
  }
}

export default createProvider
