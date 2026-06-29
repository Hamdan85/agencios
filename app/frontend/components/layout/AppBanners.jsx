import { useCallback, useEffect, useState } from 'react'
import { Download, Bell, Share, X } from 'lucide-react'
import { useCurrentUser } from '@/hooks/useAuth'
import { pushApi } from '@/api'
import { Button } from '@/components/ui/button'

// Web Push applicationServerKey must be a Uint8Array; the VAPID public key is
// delivered as a base64url string.
function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
  const raw = window.atob(base64)
  return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)))
}

const SNOOZE_KEY = 'agencios_install_snoozed_until'
const IOS_KEY = 'agencios_ios_install_dismissed'
const NOTIF_KEY = 'agencios_notif_dismissed'
const SNOOZE_DAYS = 7

function isStandalone() {
  return window.matchMedia?.('(display-mode: standalone)')?.matches || window.navigator.standalone || false
}
function isIOS() {
  return /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream
}
function installSnoozed() {
  const until = localStorage.getItem(SNOOZE_KEY)
  return until && Date.now() < Number(until)
}

// Shared bottom-of-screen card shell.
function BannerCard({ icon: Icon, color, title, children, actions }) {
  return (
    <div className="pointer-events-none fixed inset-x-0 bottom-0 z-[60] flex justify-center px-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
      <div className="animate-rise pointer-events-auto flex w-full max-w-md items-center gap-3 rounded-2xl border border-border bg-surface p-4 shadow-[0_18px_50px_-12px_rgba(17,10,36,0.35)]">
        <span className="flex size-10 shrink-0 items-center justify-center rounded-xl" style={{ background: `${color}16`, color }}>
          <Icon size={20} strokeWidth={2.2} />
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-bold text-ink">{title}</p>
          <div className="mt-0.5 text-[13px] leading-snug text-ink-muted">{children}</div>
        </div>
        <div className="flex shrink-0 items-center gap-2">{actions}</div>
      </div>
    </div>
  )
}

// Renders at most one banner at a time, by priority:
//   1. Android/Chrome install (native prompt available)
//   2. iOS install instructions (no native prompt on Safari)
//   3. Enable notifications
export default function AppBanners() {
  const { data: me } = useCurrentUser()
  const authed = !!me?.user
  const vapidKey = me?.vapid_public_key

  const [deferredPrompt, setDeferredPrompt] = useState(() => window.__installPrompt || null)
  const [installed, setInstalled] = useState(() => isStandalone())
  const [installSnooze, setInstallSnooze] = useState(() => installSnoozed())
  const [iosDismissed, setIosDismissed] = useState(() => localStorage.getItem(IOS_KEY) === '1')
  const [notifPermission, setNotifPermission] = useState(
    () => (typeof Notification === 'undefined' ? 'unsupported' : Notification.permission),
  )
  const [notifDismissed, setNotifDismissed] = useState(() => localStorage.getItem(NOTIF_KEY) === '1')

  // Pick up the install prompt (it may fire before or after this mounts).
  useEffect(() => {
    const onReady = () => setDeferredPrompt(window.__installPrompt || null)
    const onBeforeInstall = (e) => { e.preventDefault(); window.__installPrompt = e; setDeferredPrompt(e) }
    const onInstalled = () => { setInstalled(true); setDeferredPrompt(null); window.__installPrompt = null }
    window.addEventListener('agencios-install-prompt-ready', onReady)
    window.addEventListener('beforeinstallprompt', onBeforeInstall)
    window.addEventListener('appinstalled', onInstalled)
    return () => {
      window.removeEventListener('agencios-install-prompt-ready', onReady)
      window.removeEventListener('beforeinstallprompt', onBeforeInstall)
      window.removeEventListener('appinstalled', onInstalled)
    }
  }, [])

  const handleInstall = async () => {
    if (!deferredPrompt) return
    deferredPrompt.prompt()
    await deferredPrompt.userChoice.catch(() => null)
    setDeferredPrompt(null)
    window.__installPrompt = null
  }
  const snoozeInstall = () => {
    localStorage.setItem(SNOOZE_KEY, String(Date.now() + SNOOZE_DAYS * 864e5))
    setInstallSnooze(true)
  }

  const enableNotifications = useCallback(async () => {
    try {
      const permission = await Notification.requestPermission()
      setNotifPermission(permission)
      if (permission !== 'granted') return
      const reg = await navigator.serviceWorker.ready
      const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidKey),
      })
      const json = sub.toJSON()
      await pushApi.subscribe({
        endpoint: json.endpoint,
        p256dh_key: json.keys.p256dh,
        auth_key: json.keys.auth,
      })
    } catch {
      // permission denied or SW not ready — stay silent
    }
  }, [vapidKey])

  if (!authed) return null

  // 1. Android / Chrome install
  if (deferredPrompt && !installed && !installSnooze) {
    return (
      <BannerCard icon={Download} color="#7C3AED" title="Instalar agencios">
        Adicione o app à tela inicial para abrir como aplicativo.
        <div className="mt-2.5 flex gap-2">
          <Button size="sm" variant="ghost" onClick={snoozeInstall}>Agora não</Button>
          <Button size="sm" onClick={handleInstall}>Instalar</Button>
        </div>
      </BannerCard>
    )
  }

  // 2. iOS install instructions
  if (isIOS() && !installed && !iosDismissed) {
    return (
      <BannerCard
        icon={Share}
        color="#0EA5E9"
        title="Instalar agencios"
        actions={
          <Button size="sm" variant="outline" onClick={() => { localStorage.setItem(IOS_KEY, '1'); setIosDismissed(true) }}>OK</Button>
        }
      >
        Toque em <strong className="text-ink">Compartilhar</strong> e depois em <strong className="text-ink">“Adicionar à Tela de Início”</strong>.
      </BannerCard>
    )
  }

  // 3. Enable notifications
  if (notifPermission === 'default' && vapidKey && !notifDismissed) {
    return (
      <BannerCard icon={Bell} color="#EC4899" title="Ativar notificações">
        Receba avisos de tickets, prazos e publicações.
        <div className="mt-2.5 flex gap-2">
          <Button size="sm" variant="ghost" onClick={() => { localStorage.setItem(NOTIF_KEY, '1'); setNotifDismissed(true) }}>Agora não</Button>
          <Button size="sm" onClick={enableNotifications}>Permitir</Button>
        </div>
      </BannerCard>
    )
  }

  return null
}
