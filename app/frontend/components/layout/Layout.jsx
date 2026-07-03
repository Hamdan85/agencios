import { useEffect, useState } from 'react'
import { Link, Outlet, useLocation } from 'react-router-dom'
import { AlertTriangle, Menu } from 'lucide-react'
import Sidebar from './Sidebar'
import AppBanners from './AppBanners'
import Paywall from '@/pages/Billing/Paywall'
import { BrandMark } from '@/components/brand/BrandMark'
import { useCurrentUser } from '@/hooks/useAuth'
import { useBoardChannel } from '@/hooks/useRealtime'
import { cn } from '@/lib/utils'

// Routes that stay reachable even when the workspace is not billing-active, so
// the user can always pay, tweak settings, or leave. Everything else is blocked
// behind the Paywall.
const PAYWALL_ALLOWED = ['/assinatura', '/configuracoes']

export default function Layout() {
  const { data: me } = useCurrentUser()
  const location = useLocation()
  const [drawer, setDrawer] = useState(false)
  useBoardChannel(me?.workspace?.id)

  // The "total paywall": when the workspace has no active billing, block the
  // routed content behind the Paywall screen — unless the current route is an
  // explicitly-allowed one (billing / settings). `me` may still be loading, in
  // which case we let the normal shell render (ProtectedRoute already gated it).
  const blocked = me?.workspace && me.workspace.billing_active === false
    && !PAYWALL_ALLOWED.some((p) => location.pathname.startsWith(p))

  // Split-shell screens (fixed title band + a content band that fills the height
  // and scrolls itself) manage their own scrolling, so <main> must NOT scroll or
  // reserve a scrollbar gutter for them: the gutter would leave an unused strip
  // and, on the tickets hub, toggle on only for the list view — shifting the
  // header's controls when switching views. Keeping main gutter-less pins the
  // title band. The tickets hub and the calendar both use this shell.
  const selfScroll = ['/tickets', '/calendario', '/meu-calendario'].includes(location.pathname)

  // Close the drawer whenever we cross into desktop so it can't get stuck open.
  useEffect(() => {
    const mq = window.matchMedia('(min-width: 1024px)')
    const onChange = (e) => { if (e.matches) setDrawer(false) }
    mq.addEventListener('change', onChange)
    return () => mq.removeEventListener('change', onChange)
  }, [])

  // Edge-swipe to open / swipe-left to close — mirrors the adv-os drawer gesture.
  // Threshold-based on touchend: open only when the gesture starts within 32px of
  // the left edge and travels >55px right; close on a >55px left swipe. Gestures
  // dominated by vertical movement are treated as scrolls and ignored.
  useEffect(() => {
    const mq = window.matchMedia('(max-width: 1023px)')
    let startX = null, startY = null
    const onTouchStart = (e) => {
      if (!mq.matches) return
      startX = e.touches[0].clientX
      startY = e.touches[0].clientY
    }
    const onTouchEnd = (e) => {
      if (startX === null) return
      const dx = e.changedTouches[0].clientX - startX
      const dy = e.changedTouches[0].clientY - startY
      const sx = startX
      startX = null
      if (Math.abs(dy) > Math.abs(dx) * 1.2) return
      setDrawer((prev) => {
        if (!prev && sx < 32 && dx > 55) return true
        if (prev && dx < -55) return false
        return prev
      })
    }
    document.addEventListener('touchstart', onTouchStart, { passive: true })
    document.addEventListener('touchend', onTouchEnd, { passive: true })
    return () => {
      document.removeEventListener('touchstart', onTouchStart)
      document.removeEventListener('touchend', onTouchEnd)
    }
  }, [])

  // Total paywall — replaces the whole app shell (no sidebar) until billing is
  // active. The allowed routes above fall through to the normal shell below.
  if (blocked) return <Paywall />

  return (
    // h-dvh (dynamic viewport) so the layout fits the *visible* height on mobile
    // — content never sits behind the browser's bottom button bar.
    <div className="flex h-dvh overflow-hidden canvas-texture">
      {/* Desktop sidebar */}
      <div className="hidden lg:block">
        <Sidebar me={me} />
      </div>

      {/* Mobile drawer — always mounted so it slides both in and out */}
      <div className="lg:hidden" aria-hidden={!drawer}>
        <div
          onClick={() => setDrawer(false)}
          className={cn(
            'fixed inset-0 z-40 bg-brand-ink/50 backdrop-blur-sm transition-opacity duration-200',
            drawer ? 'opacity-100' : 'pointer-events-none opacity-0',
          )}
        />
        <div
          className={cn(
            'fixed inset-y-0 left-0 z-50 will-change-transform transition-transform duration-300 ease-out',
            drawer ? 'translate-x-0' : '-translate-x-full',
          )}
        >
          <Sidebar me={me} onNavigate={() => setDrawer(false)} />
        </div>
      </div>

      <div className="flex min-w-0 flex-1 flex-col">
        {/* Seat overage banner — a downgrade left more active members than the
            plan allows. Members keep access; only new tickets/projects are
            blocked (backend-enforced) until the owner reconciles seats. */}
        {me?.workspace?.over_seat_limit && (
          <div className="flex flex-wrap items-center justify-center gap-2 border-b border-danger/30 bg-danger/8 px-4 py-2 text-center text-sm font-medium text-danger">
            <AlertTriangle size={16} className="shrink-0" />
            <span>
              Este workspace tem mais membros do que o plano atual permite — novos tickets e
              campanhas estão bloqueados.
            </span>
            {me.workspace.role === 'owner' && (
              <Link to="/assinatura" className="font-semibold underline">Gerenciar plano</Link>
            )}
          </div>
        )}

        {/* Mobile topbar */}
        <header className="flex h-14 items-center justify-between border-b border-border bg-surface/80 px-4 backdrop-blur lg:hidden">
          <button
            onClick={() => setDrawer(true)}
            aria-label="Abrir menu"
            className="rounded-lg p-1.5 text-ink-secondary hover:bg-surface-muted"
          >
            <Menu size={20} />
          </button>
          <span className="flex items-center gap-1.5">
            <BrandMark className="size-6" />
            <span className="font-display text-base font-extrabold text-ink">agencios</span>
          </span>
          <span className="size-8" />
        </header>

        {/* Full-bleed shell — each page wraps its content in <Page>, which owns
            the width + padding (default "respiro", or `wide` for column-dense
            screens like the board / calendar). */}
        <main
          className={cn(
            'flex min-h-0 flex-1 flex-col overscroll-contain',
            selfScroll ? 'overflow-hidden' : 'overflow-y-auto',
          )}
          style={selfScroll ? undefined : { scrollbarGutter: 'stable' }}
        >
          <Outlet />
        </main>
      </div>

      {/* Install + notification prompts (fixed, picks one at a time) */}
      <AppBanners />
    </div>
  )
}
