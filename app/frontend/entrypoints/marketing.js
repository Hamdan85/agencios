// agencios — marketing / landing entrypoint (SSR pages)
// Pure vanilla JS: mobile nav, sticky-header elevation, FAQ accordion,
// and reveal-on-scroll. No React — these pages are server-rendered.
//
// NOTE: marketing.css is intentionally NOT imported here. It is loaded as a
// render-blocking <link> via `vite_stylesheet_tag` in the marketing layout so
// page navigations never flash unstyled content (FOUC).
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

  // ── Staggered reveal groups ───────────────────────────────────────
  // A `[data-reveal-group]` container gives each `.reveal` child an
  // incremental transition-delay so the group cascades in. Done before the
  // observer runs so the delay is present when `.is-visible` is added.
  document.querySelectorAll('[data-reveal-group]').forEach((group) => {
    const step = parseInt(group.getAttribute('data-reveal-step') || '70', 10)
    group.querySelectorAll('.reveal').forEach((el, i) => {
      el.style.setProperty('--reveal-delay', `${i * step}ms`)
    })
  })

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

  // ── Motion gate ───────────────────────────────────────────────────
  // Everything below is decorative motion — skip entirely when the user
  // prefers reduced motion (the CSS already renders a static fallback).
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches

  // ── Count-up numbers ──────────────────────────────────────────────
  // `[data-count="42"]` counts from 0 → target once scrolled into view.
  const counters = document.querySelectorAll('[data-count]')
  if (counters.length) {
    const run = (el) => {
      const target = parseFloat(el.getAttribute('data-count')) || 0
      if (reduceMotion) { el.textContent = String(target); return }
      const dur = 1400
      let start = null
      const tick = (t) => {
        if (start === null) start = t
        const p = Math.min((t - start) / dur, 1)
        const eased = 1 - Math.pow(1 - p, 3) // easeOutCubic
        el.textContent = String(Math.round(target * eased))
        if (p < 1) requestAnimationFrame(tick)
        else el.textContent = String(target)
      }
      requestAnimationFrame(tick)
    }
    if ('IntersectionObserver' in window) {
      const cio = new IntersectionObserver(
        (entries) => entries.forEach((e) => {
          if (e.isIntersecting) { run(e.target); cio.unobserve(e.target) }
        }),
        { threshold: 0.6 },
      )
      counters.forEach((el) => cio.observe(el))
    } else {
      counters.forEach(run)
    }
  }

  // ── SVG line-draw on scroll ───────────────────────────────────────
  const drawables = document.querySelectorAll('.draw-line')
  if (drawables.length && 'IntersectionObserver' in window) {
    const dio = new IntersectionObserver(
      (entries) => entries.forEach((e) => {
        if (e.isIntersecting) { e.target.classList.add('is-drawn'); dio.unobserve(e.target) }
      }),
      { threshold: 0.3 },
    )
    drawables.forEach((el) => dio.observe(el))
  } else {
    drawables.forEach((el) => el.classList.add('is-drawn'))
  }

  // ── Contextual-ticket status switcher ─────────────────────────────
  // Auto-cycles (and responds to tab clicks) through the 7 statuses,
  // toggling `[data-state-panel]` visibility + active tab styling.
  document.querySelectorAll('[data-ticket-demo]').forEach((demo) => {
    const tabs = [...demo.querySelectorAll('[data-state-tab]')]
    const panels = [...demo.querySelectorAll('[data-state-panel]')]
    if (!tabs.length) return
    let idx = 0
    let timer = null
    const show = (i) => {
      idx = (i + tabs.length) % tabs.length
      tabs.forEach((t, k) => t.setAttribute('data-active', k === idx ? 'true' : 'false'))
      panels.forEach((p, k) => { p.hidden = k !== idx })
    }
    const advance = () => show(idx + 1)
    const play = () => { if (!reduceMotion) timer = window.setInterval(advance, 2600) }
    const stop = () => { if (timer) { clearInterval(timer); timer = null } }
    tabs.forEach((t, k) => t.addEventListener('click', () => { stop(); show(k); play() }))
    demo.addEventListener('mouseenter', stop)
    demo.addEventListener('mouseleave', play)
    show(0)
    play()
  })

  // ── Typewriter (Strategist / Claude connector chat) ───────────────
  // Types each `[data-typewriter]` line in sequence, then reveals the
  // element named by `data-typewriter-then` (e.g. the generated tickets).
  const typers = document.querySelectorAll('[data-typewriter]')
  if (typers.length) {
    const typeInto = (el) => new Promise((resolve) => {
      const full = el.getAttribute('data-typewriter') || el.textContent
      if (reduceMotion) { el.textContent = full; resolve(); return }
      el.textContent = ''
      el.classList.add('anim-caret')
      let i = 0
      const step = () => {
        el.textContent = full.slice(0, i++)
        if (i <= full.length) window.setTimeout(step, 18 + Math.random() * 32)
        else { el.classList.remove('anim-caret'); resolve() }
      }
      step()
    })
    const runSequence = async (root) => {
      const lines = [...root.querySelectorAll('[data-typewriter]')]
      for (const line of lines) {
        line.closest('[data-type-line]')?.removeAttribute('hidden')
        // eslint-disable-next-line no-await-in-loop
        await typeInto(line)
      }
      const then = root.querySelector('[data-typewriter-then]')
      if (then) then.removeAttribute('hidden')
    }
    document.querySelectorAll('[data-typewriter-root]').forEach((root) => {
      if (!('IntersectionObserver' in window)) { runSequence(root); return }
      const tio = new IntersectionObserver(
        (entries) => entries.forEach((e) => {
          if (e.isIntersecting) { runSequence(root); tio.unobserve(e.target) }
        }),
        { threshold: 0.4 },
      )
      tio.observe(root)
    })
  }

  // ── Hero pointer-tilt ─────────────────────────────────────────────
  // Subtle 3D tilt following the cursor; off on touch + reduced motion.
  const tiltEl = document.querySelector('[data-tilt]')
  if (tiltEl && !reduceMotion && window.matchMedia('(hover: hover)').matches) {
    let raf = null
    const onMove = (e) => {
      if (raf) return
      raf = requestAnimationFrame(() => {
        const r = tiltEl.getBoundingClientRect()
        const px = (e.clientX - r.left) / r.width - 0.5
        const py = (e.clientY - r.top) / r.height - 0.5
        tiltEl.style.setProperty('--tx', `${px * 7}deg`)
        tiltEl.style.setProperty('--ty', `${-py * 7}deg`)
        raf = null
      })
    }
    const reset = () => {
      tiltEl.style.setProperty('--tx', '0deg')
      tiltEl.style.setProperty('--ty', '0deg')
    }
    const zone = tiltEl.closest('[data-tilt-zone]') || tiltEl
    zone.addEventListener('pointermove', onMove)
    zone.addEventListener('pointerleave', reset)
  }
})
