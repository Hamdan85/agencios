import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { authApi, accountApi } from '@/api'
import { keys } from '@/api/queryKeys'
import analytics, { EVENTS } from '@/lib/analytics'
import { applyLocale } from '@/i18n'

export function useCurrentUser() {
  return useQuery({
    queryKey: keys.me(),
    queryFn: async () => {
      const data = await authApi.me()
      applyLocale(data?.user?.locale)
      return data
    },
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
      applyLocale(data?.user?.locale)
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
      applyLocale(data?.user?.locale)
      // The primary acquisition conversion + the trial it kicks off.
      analytics.track(EVENTS.SIGN_UP, { method: 'password' })
      analytics.track(EVENTS.TRIAL_STARTED, { plan: data?.workspace?.plan })
    },
  })
}

// Password recovery (both public — the user is signed out). Neither touches the
// session cache; the reset flow ends by sending the user to /login.
export function useForgotPassword() {
  return useMutation({
    mutationFn: (email) => authApi.forgotPassword(email),
  })
}

export function useResetPassword() {
  return useMutation({
    mutationFn: ({ token, password }) => authApi.resetPassword(token, password),
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

// ── Account (the signed-in user's own profile) ────────────────────────
// Profile + avatar mutations return the full `/me` payload, so we prime the
// cache with it directly (no refetch needed).
export function useUpdateAccount() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (data) => accountApi.update(data),
    onSuccess: (data, variables) => {
      qc.setQueryData(keys.me(), data)
      if (variables?.user?.locale) {
        applyLocale(data?.user?.locale)
        // Server-rendered copy (API errors, system notes) changes language too.
        qc.invalidateQueries()
      }
      toast.success('Perfil atualizado.')
    },
    onError: (e) => toast.error(e?.error || 'Erro ao atualizar o perfil.'),
  })
}

export function useUpdateAvatar() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (file) => accountApi.updateAvatar(file),
    onSuccess: (data) => { qc.setQueryData(keys.me(), data); toast.success('Foto atualizada.') },
    onError: (e) => toast.error(e?.error || 'Erro ao enviar a foto.'),
  })
}

export function useUpdatePassword() {
  return useMutation({
    mutationFn: (data) => accountApi.updatePassword(data),
    onSuccess: () => toast.success('Senha alterada.'),
    onError: (e) => toast.error(e?.error || 'Erro ao alterar a senha.'),
  })
}

export function useRequestEmailChange() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (data) => accountApi.changeEmail(data),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: keys.me() })
      toast.success('Enviamos um link de confirmação para o novo e-mail.')
    },
    onError: (e) => toast.error(e?.error || 'Erro ao solicitar a troca de e-mail.'),
  })
}

export function useConfirmEmailChange() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (token) => accountApi.confirmEmailChange(token),
    onSuccess: () => qc.invalidateQueries({ queryKey: keys.me() }),
  })
}
