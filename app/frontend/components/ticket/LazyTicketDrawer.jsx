import { lazy, Suspense, useEffect, useState } from 'react'

// The ticket detail subtree is heavy (a markdown renderer + a lot of icons) —
// ~75 kB gzipped. Loading it statically made every screen that can open the
// drawer (the tickets hub, the calendar) pull it on navigation, before any
// ticket was opened. Splitting it out keeps those pages light.
const TicketDrawer = lazy(() => import('./TicketDrawer'))

const prefetch = () => { import('./TicketDrawer') }

// Drop-in replacement for <TicketDrawer>: keeps the heavy bundle out of the
// page's initial load. The chunk is warmed once the browser is idle (so the
// first open is instant) and mounted on first open; it stays mounted afterwards
// so the sheet's close animation still plays.
export default function LazyTicketDrawer(props) {
  const [mounted, setMounted] = useState(false)

  useEffect(() => { if (props.open) setMounted(true) }, [props.open])

  // Warm the chunk when idle, off the initial render's critical path.
  useEffect(() => {
    const ric = window.requestIdleCallback
    if (ric) {
      const id = ric(prefetch)
      return () => window.cancelIdleCallback?.(id)
    }
    const t = setTimeout(prefetch, 1500)
    return () => clearTimeout(t)
  }, [])

  if (!mounted) return null
  return (
    <Suspense fallback={null}>
      <TicketDrawer {...props} />
    </Suspense>
  )
}
