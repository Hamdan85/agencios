import { useCallback, useMemo, useState } from 'react'

// Tracks a set of selected row ids for a list with multi-select + bulk actions.
// `toggle` flips one id; `set` replaces the whole selection (e.g. select-all);
// `clear` empties it. `count` / `list` derive from the current Set.
export function useSelection() {
  const [ids, setIds] = useState(() => new Set())

  const toggle = useCallback((id) => {
    setIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }, [])

  const set = useCallback((nextIds) => setIds(new Set(nextIds)), [])
  const clear = useCallback(() => setIds(new Set()), [])
  const has = useCallback((id) => ids.has(id), [ids])

  const list = useMemo(() => [...ids], [ids])

  return { ids, has, toggle, set, clear, count: ids.size, list }
}

export default useSelection
