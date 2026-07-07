import { useState } from 'react'
import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { toast } from 'sonner'
import { socialApi, meetingsApi, invoicesApi, settingsApi, billingApi, creditsApi, pricingApi, accountApi } from '@/api'
import { keys } from '@/api/queryKeys'
import analytics, { EVENTS } from '@/lib/analytics'
import { onErr } from './shared'

// ── Social accounts (connected per client) ─────────────────────
export const useSocialAccounts = (clientId) =>
  useQuery({
    queryKey: keys.socialAccounts(clientId),
    queryFn: () => socialApi.list(clientId),
    select: (d) => d.social_accounts,
    enabled: !!clientId,
  })

// Connect opens the network's OAuth flow in a popup. When the popup callback
// posts an 'oauth_connected' message, we close the popup and refresh the client.
export function useSocialAccountMutations(clientId) {
  const qc = useQueryClient()
  const inv = () => qc.invalidateQueries({ queryKey: keys.client(clientId) })
  const [connecting, setConnecting] = useState(false)

  // The popup MUST be opened synchronously inside the click handler — browsers
  // block `window.open()` that isn't tied to a live user gesture, and the
  // authorize_url fetch resolves a tick later, so opening it in the mutation
  // callback was being silently blocked (the "nothing happens" bug). We open a
  // blank popup on click and only point it at the OAuth URL once it arrives.
  function openBlankPopup() {
    const w = 600
    const h = 700
    const left = Math.round(window.screenX + (window.outerWidth - w) / 2)
    const top = Math.round(window.screenY + (window.outerHeight - h) / 2)
    return window.open('about:blank', 'oauth_popup', `width=${w},height=${h},left=${left},top=${top},toolbar=no,menubar=no`)
  }

  // Facebook's OAuth hop can sever the popup's `window.opener` (COOP), so the
  // popup can't reliably postMessage us or close itself. We listen on
  // same-origin side channels that survive that — BroadcastChannel + a
  // localStorage ping — plus the legacy postMessage, and WE close the popup
  // (the opener keeps the reference). A poll on `popup.closed` is the backstop.
  function trackOAuthPopup(popup) {
    let done = false
    const bc = 'BroadcastChannel' in window ? new BroadcastChannel('agencios_oauth') : null

    function cleanup() {
      window.removeEventListener('message', onMessage)
      window.removeEventListener('storage', onStorage)
      if (bc) bc.close()
      if (poll) window.clearInterval(poll)
    }

    function finish(payload) {
      if (done) return
      done = true
      cleanup()
      try { if (popup && !popup.closed) popup.close() } catch { /* cross-origin */ }
      if (payload?.error) {
        toast.error(payload.error === 'no_instagram'
          ? 'Esta Página não tem uma conta Instagram Business vinculada.'
          : 'Erro ao conectar. Tente novamente.')
      } else {
        inv()
        toast.success('Conta conectada com sucesso!')
      }
    }

    const onMessage = (e) => {
      if (e.origin !== window.location.origin) return
      if (e.data?.type === 'oauth_connected') finish(e.data)
    }
    const onStorage = (e) => {
      if (e.key !== 'agencios_oauth' || !e.newValue) return
      try { finish(JSON.parse(e.newValue)) } catch { /* ignore */ }
    }

    window.addEventListener('message', onMessage)
    window.addEventListener('storage', onStorage)
    if (bc) bc.onmessage = (e) => { if (e.data?.type === 'oauth_connected') finish(e.data) }

    // Backstop: if the popup is closed manually (or the channels are blocked),
    // stop listening and refresh so a completed connection still shows up.
    const poll = window.setInterval(() => {
      if (popup && popup.closed) { cleanup(); if (!done) { done = true; inv() } }
    }, 800)
  }

  function connect(network) {
    const popup = openBlankPopup()
    setConnecting(true)
    socialApi.authorizeUrl(clientId, network)
      .then((d) => {
        if (!d?.url) throw new Error('missing authorize url')
        if (popup) { popup.location.href = d.url; trackOAuthPopup(popup) }
        else window.open(d.url, '_blank') // popup blocked: best-effort new tab
      })
      .catch((err) => {
        try { popup?.close() } catch { /* cross-origin */ }
        toast.error(err?.error || 'Não foi possível iniciar a conexão.')
      })
      .finally(() => setConnecting(false))
  }

  return {
    connect,
    connecting,
    disconnect: useMutation({
      mutationFn: (id) => socialApi.destroy(clientId, id),
      onSuccess: () => { inv(); toast.success('Conta desconectada.') },
      onError: onErr('Erro ao desconectar.'),
    }),
    reconnect: useMutation({
      mutationFn: (id) => socialApi.reconnect(clientId, id),
      onSuccess: () => { inv(); toast.success('Conta reconectada.') },
      onError: onErr('Erro ao reconectar.'),
    }),
  }
}

// ── Meetings ───────────────────────────────────────────────────
export const useMeetings = (filters = {}) =>
  useQuery({ queryKey: keys.meetings(filters), queryFn: () => meetingsApi.list(filters), select: (d) => d.meetings })

export function useMeetingMutations() {
  const qc = useQueryClient()
  const inv = () => { qc.invalidateQueries({ queryKey: ['meetings'] }); qc.invalidateQueries({ queryKey: ['calendar'] }) }
  return {
    create: useMutation({ mutationFn: meetingsApi.create, onSuccess: () => { inv(); analytics.track(EVENTS.MEETING_SCHEDULED); toast.success('Reunião agendada!') }, onError: onErr('Erro.') }),
    update: useMutation({ mutationFn: ({ id, data }) => meetingsApi.update(id, data), onSuccess: inv, onError: onErr('Erro.') }),
    destroy: useMutation({ mutationFn: meetingsApi.destroy, onSuccess: inv, onError: onErr('Erro.') }),
  }
}

// ── Invoices ───────────────────────────────────────────────────
export const useInvoices = (filters = {}) =>
  useQuery({ queryKey: keys.invoices(filters), queryFn: () => invoicesApi.list(filters), select: (d) => d.invoices })

export function useInvoiceMutations() {
  const qc = useQueryClient()
  const inv = () => qc.invalidateQueries({ queryKey: ['invoices'] })
  return {
    create: useMutation({ mutationFn: invoicesApi.create, onSuccess: () => { inv(); analytics.track(EVENTS.INVOICE_CREATED); toast.success('Cobrança criada!') }, onError: onErr('Erro.') }),
    cancel: useMutation({ mutationFn: invoicesApi.cancel, onSuccess: inv, onError: onErr('Erro.') }),
    markPaid: useMutation({ mutationFn: invoicesApi.markPaid, onSuccess: () => { inv(); toast.success('Cobrança marcada como paga.') }, onError: onErr('Erro.') }),
    paymentLink: useMutation({ mutationFn: invoicesApi.paymentLink, onSuccess: () => { inv(); toast.success('Link de pagamento gerado!') }, onError: onErr('Erro ao gerar link.') }),
    sendPaymentLink: useMutation({ mutationFn: invoicesApi.sendPaymentLink, onSuccess: () => { inv(); toast.success('Link de pagamento enviado ao cliente!') }, onError: onErr('Erro ao enviar o link.') }),
  }
}

// ── Settings ───────────────────────────────────────────────────
export const useSettings = () => useQuery({ queryKey: keys.settings(), queryFn: settingsApi.get })

// Google Calendar is a personal integration (meetings are user-level): the
// connection lives on the user, surfaced on /conta and read from /me.
export function useGoogleCalendarMutations() {
  const qc = useQueryClient()
  const inv = () => qc.invalidateQueries({ queryKey: keys.me() })

  function openCalendarPopup(url) {
    const w = 600, h = 700
    const left = Math.round(window.screenX + (window.outerWidth - w) / 2)
    const top = Math.round(window.screenY + (window.outerHeight - h) / 2)
    const popup = window.open(url, 'calendar_oauth', `width=${w},height=${h},left=${left},top=${top},toolbar=no,menubar=no`)

    const onMessage = (e) => {
      if (e.origin !== window.location.origin) return
      if (e.data?.type !== 'calendar_connected') return
      window.removeEventListener('message', onMessage)
      if (popup && !popup.closed) popup.close()
      if (e.data.error) {
        toast.error('Erro ao conectar o Google Calendar.')
      } else {
        inv()
        toast.success('Google Calendar conectado!')
      }
    }
    window.addEventListener('message', onMessage)
  }

  return {
    connect: useMutation({
      mutationFn: accountApi.calendarAuthorizeUrl,
      onSuccess: (d) => { if (d?.url) openCalendarPopup(d.url) },
      onError: onErr('Não foi possível iniciar a conexão.'),
    }),
    disconnect: useMutation({
      mutationFn: accountApi.calendarDisconnect,
      onSuccess: () => { inv(); toast.success('Google Calendar desconectado.') },
      onError: onErr('Erro ao desconectar.'),
    }),
  }
}

export function useSettingsMutation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: settingsApi.update,
    onSuccess: () => { qc.invalidateQueries({ queryKey: keys.settings() }); qc.invalidateQueries({ queryKey: keys.me() }); toast.success('Configurações salvas!') },
    onError: onErr('Erro ao salvar.'),
  })
}

export function useSettingsBrandAssetsMutation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: settingsApi.uploadBrandAssets,
    onSuccess: () => { qc.invalidateQueries({ queryKey: keys.settings() }); qc.invalidateQueries({ queryKey: keys.me() }) },
    onError: onErr('Erro ao enviar o logo.'),
  })
}

// ── Billing ────────────────────────────────────────────────────
export const useBilling = () => useQuery({ queryKey: keys.billing(), queryFn: billingApi.get })
export function useBillingMutations() {
  const qc = useQueryClient()
  const inv = () => { qc.invalidateQueries({ queryKey: keys.billing() }); qc.invalidateQueries({ queryKey: keys.me() }) }
  return {
    // Start Stripe Checkout for a workspace with no active subscription (or to
    // subscribe from the paywall). Accepts either a bare plan key or
    // `{ plan, interval }` (interval: 'month' | 'year', default 'month').
    // Redirects the browser to the returned url.
    checkout: useMutation({
      mutationFn: (arg) => {
        const { plan, interval } = typeof arg === 'string' ? { plan: arg } : (arg || {})
        return billingApi.checkout(plan, interval || 'month')
      },
      onSuccess: (data, arg) => {
        const plan = typeof arg === 'string' ? arg : arg?.plan
        analytics.track(EVENTS.SUBSCRIBE, { plan })
        if (data?.url) window.location.href = data.url
      },
      onError: onErr('Erro ao iniciar o checkout.'),
    }),
    // change_plan returns EITHER { checkout_url } (redirect — new subscriber) OR
    // { subscription } (existing subscriber swapped the plan). Handle both.
    // Accepts a bare plan key or `{ plan, interval }`.
    changePlan: useMutation({
      mutationFn: (arg) => {
        const { plan, interval } = typeof arg === 'string' ? { plan: arg } : (arg || {})
        return billingApi.changePlan(plan, interval || 'month')
      },
      onSuccess: (data, arg) => {
        const plan = typeof arg === 'string' ? arg : arg?.plan
        analytics.track(EVENTS.SUBSCRIBE, { plan })
        if (data?.checkout_url) { window.location.href = data.checkout_url; return }
        inv()
        toast.success('Plano atualizado!')
      },
      onError: onErr('Erro.'),
    }),
    cancel: useMutation({ mutationFn: billingApi.cancel, onSuccess: () => { inv(); toast.success('Assinatura cancelada ao fim do período.') }, onError: onErr('Erro.') }),
    reactivate: useMutation({ mutationFn: billingApi.reactivate, onSuccess: () => { inv(); toast.success('Assinatura reativada!') }, onError: onErr('Erro.') }),
    // Opens the Stripe customer portal when the backend returns a url (payment
    // method / invoices). No-op if the portal isn't configured yet.
    portal: useMutation({
      mutationFn: billingApi.portal,
      onSuccess: (data) => {
        if (data?.url) window.location.href = data.url
        else toast.info('Portal de pagamento indisponível no momento.')
      },
      onError: onErr('Erro ao abrir o portal.'),
    }),
  }
}

// ── Credits (prepaid wallet for video/image generation) ────────
export const useCredits = () => useQuery({ queryKey: keys.credits(), queryFn: creditsApi.get })

// Credit-usage breakdown for the "Uso" tab (spend by kind + trend + recent runs).
// `params` carries the time range plus the recent-log filters (kind/status/page),
// so changing a filter refetches; previous data is kept for smooth paging.
export const useCreditUsage = (params = {}) =>
  useQuery({
    queryKey: keys.creditUsage(params),
    queryFn: () => creditsApi.usage(params),
    placeholderData: keepPreviousData,
  })

export function useCreditsMutations() {
  return {
    // Buy a credit pack via Stripe Checkout — redirects to the returned url.
    checkout: useMutation({
      mutationFn: creditsApi.checkout,
      onSuccess: (data) => { if (data?.url) window.location.href = data.url },
      onError: onErr('Erro ao iniciar a compra de créditos.'),
    }),
  }
}

// ── Public pricing catalog (drives the paywall plan picker) ────
export const usePricing = () =>
  useQuery({ queryKey: keys.pricing(), queryFn: pricingApi.get, staleTime: 10 * 60_000 })
