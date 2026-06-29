import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import { cn } from '@/lib/utils'

// Wraps a horizontally scrollable region and casts a soft depth shadow at
// whichever edge still hides content — content appears to slide *under* a raised
// edge (an outward 3D shadow), rather than the cards fading to transparent. The
// overlay is pointer-events-none so it never intercepts drag/click, and sizing
// is pure flex (no percentage heights) so the region fills its parent exactly.
export function ScrollShadow({ className, viewportClassName, children, ...props }) {
  const ref = useRef(null)
  const [edges, setEdges] = useState({ left: false, right: false })

  const update = useCallback(() => {
    const el = ref.current
    if (!el) return
    const { scrollLeft, scrollWidth, clientWidth } = el
    const max = scrollWidth - clientWidth
    setEdges({ left: scrollLeft > 1, right: scrollLeft < max - 1 })
  }, [])

  // Recompute whenever the rendered children change (columns added/removed).
  useLayoutEffect(() => { update() }, [update, children])

  useEffect(() => {
    const el = ref.current
    if (!el) return
    update()
    el.addEventListener('scroll', update, { passive: true })
    const ro = new ResizeObserver(update)
    ro.observe(el)
    window.addEventListener('resize', update)
    return () => {
      el.removeEventListener('scroll', update)
      ro.disconnect()
      window.removeEventListener('resize', update)
    }
  }, [update])

  // Inset shadows hug the edge (negative spread) and read as a cast shadow / fold,
  // signalling "there's more beyond this edge" without dimming the cards.
  const shadow = [
    edges.left ? 'inset 22px 0 20px -22px rgba(17,10,36,0.4)' : null,
    edges.right ? 'inset -22px 0 20px -22px rgba(17,10,36,0.4)' : null,
  ].filter(Boolean).join(', ')

  return (
    <div className={cn('relative flex min-h-0 min-w-0 flex-col', className)}>
      <div ref={ref} className={cn('min-h-0 min-w-0 flex-1', viewportClassName)} {...props}>
        {children}
      </div>
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 transition-[box-shadow] duration-300"
        style={{ boxShadow: shadow || undefined }}
      />
    </div>
  )
}

export default ScrollShadow
