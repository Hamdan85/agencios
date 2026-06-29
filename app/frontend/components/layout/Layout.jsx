import { useEffect, useState } from 'react'
import { Outlet } from 'react-router-dom'
import { Menu } from 'lucide-react'
import Sidebar from './Sidebar'
import AppBanners from './AppBanners'
import { BrandMark } from '@/components/brand/BrandMark'
import { useCurrentUser } from '@/hooks/useAuth'
import { useBoardChannel } from '@/hooks/useRealtime'
import { cn } from '@/lib/utils'

export default function Layout() {
  const { data: me } = useCurrentUser()
  const [drawer, setDrawer] = useState(false)
  useBoardChannel(me?.workspace?.id)

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

        <main className="flex min-h-0 flex-1 flex-col overflow-y-auto overscroll-contain" style={{ scrollbarGutter: 'stable' }}>
          {/* Generous, safe-area-aware bottom padding on mobile so every page's
              last component (and any bottom button bar) clears the browser bar /
              home indicator. Desktop keeps the original py-9. */}
          <div className="mx-auto flex w-full max-w-7xl flex-1 flex-col px-5 pt-7 pb-[calc(env(safe-area-inset-bottom)+4rem)] sm:px-8 sm:py-9">
            <Outlet />
          </div>
        </main>
      </div>

      {/* Install + notification prompts (fixed, picks one at a time) */}
      <AppBanners />
    </div>
  )
}
