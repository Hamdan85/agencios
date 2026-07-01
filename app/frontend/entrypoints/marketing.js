// agencios — marketing / landing entrypoint (SSR pages)
// Pure vanilla JS: mobile nav, sticky-header elevation, FAQ accordion,
// and reveal-on-scroll. No React — these pages are server-rendered.
import './marketing.css'
import analytics, { EVENTS } from '@/lib/analytics'
import { bootAnalytics } from '@/lib/analytics/boot'

// Signal JS availability so reveal-on-scroll can hide content without
// penalising no-JS visitors (CSS gates the hidden state behind `html.js`).
document.documentElement.classList.add('js')

// ── Analytics (consent-gated; buffered until the user accepts) ───────
bootAnalytics()
analytics.page(window.location.pathname)
// Treat any "create account" CTA as top-of-funnel lead intent. Delegated so we
// don't have to annotate every button across the marketing ERB.
document.addEventListener('click', (e) => {
  const link = e.target.closest('a[href^="/cadastro"]')
  if (link) analytics.track(EVENTS.CTA_CLICK, { cta: 'signup', location: 'marketing' })
})

function onReady(fn) {
  if (document.readyState !== 'loading') fn()
  else document.addEventListener('DOMContentLoaded', fn)
}

onReady(() => {
  // ── Mobile navigation drawer ──────────────────────────────────────
  const nav = document.querySelector('[data-mobile-nav]')
  const setNav = (open) => {
    if (!nav) return
    nav.classList.toggle('hidden', !open)
    document.body.classList.toggle('overflow-hidden', open)
  }
  document.querySelectorAll('[data-mobile-open]').forEach((b) => b.addEventListener('click', () => setNav(true)))
  document.querySelectorAll('[data-mobile-close]').forEach((b) => b.addEventListener('click', () => setNav(false)))
  nav?.querySelectorAll('a').forEach((a) => a.addEventListener('click', () => setNav(false)))

  // ── Sticky header elevation ───────────────────────────────────────
  const header = document.querySelector('[data-header]')
  if (header) {
    const onScroll = () => header.classList.toggle('is-scrolled', window.scrollY > 8)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
  }

  // ── FAQ accordion ─────────────────────────────────────────────────
  document.querySelectorAll('[data-accordion-trigger]').forEach((trigger) => {
    trigger.addEventListener('click', () => {
      const item = trigger.closest('[data-accordion-item]')
      const panel = item?.querySelector('[data-accordion-panel]')
      if (!item || !panel) return
      const open = item.toggleAttribute('data-open')
      panel.style.maxHeight = open ? `${panel.scrollHeight}px` : null
      trigger.setAttribute('aria-expanded', open ? 'true' : 'false')
    })
  })

  // ── Pricing interval toggle (Mensal / Anual) ──────────────────────
  const pricing = document.querySelector('[data-pricing]')
  if (pricing) {
    const buttons = pricing.querySelectorAll('[data-pricing-interval]')
    const setInterval = (interval) => {
      pricing.setAttribute('data-interval', interval)
      const annual = interval === 'year'
      buttons.forEach((b) => {
        const on = b.getAttribute('data-pricing-interval') === interval
        b.setAttribute('aria-selected', on ? 'true' : 'false')
        b.classList.toggle('bg-brand', on)
        b.classList.toggle('text-white', on)
        b.classList.toggle('shadow-sm', on)
        b.classList.toggle('text-ink-secondary', !on)
      })
      pricing.querySelectorAll('[data-price-month]').forEach((el) => { el.hidden = annual })
      pricing.querySelectorAll('[data-price-year]').forEach((el) => { el.hidden = !annual })
      pricing.querySelectorAll('[data-price-year-caption]').forEach((el) => { el.hidden = !annual })
    }
    buttons.forEach((b) => b.addEventListener('click', () => setInterval(b.getAttribute('data-pricing-interval'))))
    setInterval('month')
  }

  // ── Reveal on scroll ──────────────────────────────────────────────
  const reveals = document.querySelectorAll('.reveal')
  if ('IntersectionObserver' in window && reveals.length) {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) {
            e.target.classList.add('is-visible')
            io.unobserve(e.target)
          }
        })
      },
      { rootMargin: '0px 0px -8% 0px', threshold: 0.05 },
    )
    reveals.forEach((el) => io.observe(el))
  } else {
    reveals.forEach((el) => el.classList.add('is-visible'))
  }
})
