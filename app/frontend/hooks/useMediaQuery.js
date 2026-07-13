import { useEffect, useState } from 'react'

// Subscribe to a CSS media query.
//
// Mobile behaviour belongs in Tailwind `max-sm:` classes — reach for this ONLY when
// the difference can't be expressed in CSS: rendering a different component (a bottom
// Sheet instead of a Dialog) or passing a different prop value (a Textarea's maxRows,
// which the auto-grow writes to `style.height` inline, so CSS can't clamp it).
export function useMediaQuery(query) {
  const [matches, setMatches] = useState(() => window.matchMedia(query).matches)

  useEffect(() => {
    const mql = window.matchMedia(query)
    const onChange = (e) => setMatches(e.matches)
    setMatches(mql.matches) // the query may have changed between render and effect
    mql.addEventListener('change', onChange)
    return () => mql.removeEventListener('change', onChange)
  }, [query])

  return matches
}

// Below the project's `sm` breakpoint (40rem / 640px) — i.e. phones. Mirrors `max-sm:`.
export const useIsMobile = () => useMediaQuery('(max-width: 639.98px)')
