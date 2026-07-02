import { useCallback, useMemo } from 'react'
import { useSearchParams } from 'react-router-dom'

// Sync a plain filter object with the URL query string, restricted to a known
// set of keys. Params outside `keys` (e.g. `ticket`, `planejar`) are left
// untouched, so filters, the open drawer, and one-shot flags can share the URL.
//
// `keys` MUST be a stable reference (define it at module scope) so the derived
// object / setter identities only change when the URL actually changes.
export function useUrlFilters(keys) {
  const [searchParams, setSearchParams] = useSearchParams()

  const filters = useMemo(() => {
    const f = {}
    keys.forEach((k) => {
      const v = searchParams.get(k)
      if (v != null && v !== '') f[k] = v
    })
    return f
  }, [searchParams, keys])

  const setFilters = useCallback(
    (next) => {
      const value = typeof next === 'function' ? next(filters) : next
      setSearchParams(
        (prev) => {
          const sp = new URLSearchParams(prev)
          keys.forEach((k) => {
            const v = value?.[k]
            if (v == null || v === '') sp.delete(k)
            else sp.set(k, v)
          })
          return sp
        },
        { replace: true },
      )
    },
    [setSearchParams, keys, filters],
  )

  return [filters, setFilters]
}

// Sync a single URL query param with a piece of state (e.g. the open ticket in a
// drawer). Opening pushes a history entry so the browser Back button closes it;
// closing replaces so it doesn't leave a dangling forward entry.
export function useUrlParam(name) {
  const [searchParams, setSearchParams] = useSearchParams()
  const value = searchParams.get(name)

  const setValue = useCallback(
    (v, { replace = false } = {}) => {
      setSearchParams(
        (prev) => {
          const sp = new URLSearchParams(prev)
          if (v == null || v === '') sp.delete(name)
          else sp.set(name, String(v))
          return sp
        },
        { replace },
      )
    },
    [setSearchParams, name],
  )

  return [value, setValue]
}
