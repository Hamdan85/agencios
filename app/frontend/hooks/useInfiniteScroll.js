import { useEffect, useRef } from 'react'

// Infinite scroll for a TanStack useInfiniteQuery: returns the ref to put on
// an end-of-list sentinel <div>; the next page loads as it nears the viewport.
// Pass anything that changes the list height (e.g. the item count) in `deps`
// so the observer re-arms after a render.
export function useInfiniteScroll({ hasNextPage, isFetchingNextPage, fetchNextPage, deps = [] }) {
  const sentinelRef = useRef(null)
  useEffect(() => {
    const el = sentinelRef.current
    if (!el) return
    const io = new IntersectionObserver(
      (entries) => { if (entries[0].isIntersecting && hasNextPage && !isFetchingNextPage) fetchNextPage() },
      { rootMargin: '300px' },
    )
    io.observe(el)
    return () => io.disconnect()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hasNextPage, isFetchingNextPage, fetchNextPage, ...deps])
  return sentinelRef
}
