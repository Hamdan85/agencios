import { Navigate, Outlet } from 'react-router-dom'
import { useCurrentUser } from '@/hooks/useAuth'
import { PageLoader } from '@/components/ui/feedback'

export default function ProtectedRoute() {
  const { data, isLoading, isError } = useCurrentUser()

  if (isLoading) return <PageLoader />
  if (isError || !data?.user) return <Navigate to="/login" replace />
  return <Outlet />
}

export function GuestRoute() {
  const { data, isLoading } = useCurrentUser()
  if (isLoading) return <PageLoader />
  if (data?.user) return <Navigate to="/painel" replace />
  return <Outlet />
}
