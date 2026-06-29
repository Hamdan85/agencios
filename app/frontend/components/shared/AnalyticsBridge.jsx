import { useEffect, useRef } from 'react'
import { useLocation } from 'react-router-dom'
import analytics from '@/lib/analytics'
import { useCurrentUser } from '@/hooks/useAuth'

// Drives the two ambient analytics signals inside the SPA:
//   • a page view on every React Router navigation (paths are masked in the
//     facade, so record ids never leak), and
//   • `identify` once the current user is known (and again if it changes).
// Renders nothing. Mounted once near the router root. The facade buffers until
// consent is granted, so calls here are always safe.
export default function AnalyticsBridge() {
  const location = useLocation()
  const { data: me } = useCurrentUser()
  const identified = useRef(null)

  useEffect(() => {
    analytics.page(location.pathname + location.search)
  }, [location.pathname, location.search])

  useEffect(() => {
    const user = me?.user
    if (!user?.id || identified.current === user.id) return
    identified.current = user.id
    analytics.identify(user.id, {
      email: user.email,
      name: user.name || user.display_name,
      role: me?.membership?.role || me?.workspace?.role,
      plan: me?.workspace?.plan,
      workspace_id: me?.workspace?.id,
      is_staff: user.staff,
    })
  }, [me?.user?.id, me?.membership?.role, me?.workspace?.id, me?.workspace?.plan])

  return null
}
