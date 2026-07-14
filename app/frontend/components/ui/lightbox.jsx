import { createContext, lazy, Suspense, useCallback, useContext, useMemo, useState } from 'react'

// The lightbox is mounted ONCE at the app root and opened imperatively from
// anywhere: `const { open } = useLightbox(); open(items, index)`. No call site
// keeps its own {open, index, items} state, and nothing renders a second copy.
//
// Items are MediaItems — build them with `creativeToMedia` / `attachmentToMedia`
// / `urlToMedia` from `@/lib/media`.
//
// The overlay (and, deeper, react-pdf) is code-split: opening media is the only
// thing that pulls it in, so the app shell stays light.
const LightboxView = lazy(() => import('./lightbox-view'))

const LightboxContext = createContext(null)

export function useLightbox() {
  const ctx = useContext(LightboxContext)
  if (!ctx) throw new Error('useLightbox must be used inside <LightboxProvider>')
  return ctx
}

export function LightboxProvider({ children }) {
  const [state, setState] = useState(null) // { items, index } while open

  const open = useCallback((items, index = 0) => {
    const list = (Array.isArray(items) ? items : [items]).filter((it) => it?.url)
    if (!list.length) return
    setState({ items: list, index: Math.min(Math.max(0, index), list.length - 1) })
  }, [])

  const close = useCallback(() => setState(null), [])

  const api = useMemo(() => ({ open, close }), [open, close])

  return (
    <LightboxContext.Provider value={api}>
      {children}
      {state && (
        <Suspense fallback={null}>
          <LightboxView items={state.items} initialIndex={state.index} onClose={close} />
        </Suspense>
      )}
    </LightboxContext.Provider>
  )
}
