import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { authApi } from '@/api'
import { keys } from '@/api/queryKeys'
import analytics, { EVENTS } from '@/lib/analytics'

export function useCurrentUser() {
  return useQuery({
    queryKey: keys.me(),
    queryFn: authApi.me,
    retry: false,
    staleTime: 5 * 60_000,
  })
}

export function useLogin() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ email, password }) => authApi.login(email, password),
    onSuccess: (data) => {
      qc.setQueryData(keys.me(), data)
      analytics.track(EVENTS.LOGIN, { method: 'password' })
    },
  })
}

export function useRegister() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (data) => authApi.register(data),
    onSuccess: (data) => {
      qc.setQueryData(keys.me(), data)
      // The primary acquisition conversion + the trial it kicks off.
      analytics.track(EVENTS.SIGN_UP, { method: 'password' })
      analytics.track(EVENTS.TRIAL_STARTED, { plan: data?.workspace?.plan })
    },
  })
}

export function useLogout() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => authApi.logout(),
    onSuccess: () => {
      analytics.track(EVENTS.LOGOUT)
      analytics.reset()
      qc.clear()
      window.location.href = '/login'
    },
  })
}
