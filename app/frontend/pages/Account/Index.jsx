import { useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useTranslation, Trans } from 'react-i18next'
import {
  UserRound, Shield, Bot, Save, Camera, Mail, Check, Copy, RefreshCw,
  ShieldCheck, Sparkles, Trash2, KeyRound, AlertCircle, Calendar, Languages,
} from 'lucide-react'
import {
  useCurrentUser, useUpdateAccount, useUpdateAvatar, useUpdatePassword, useRequestEmailChange,
} from '@/hooks/useAuth'
import {
  useConnections, useRevokeConnection, useMcpConnector, useRotateMcpConnector,
  useGoogleCalendarMutations,
} from '@/hooks/useData'
import { PageHeader } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Avatar } from '@/components/ui/avatar'
import { useCopyToClipboard } from '@/components/ui/copy-button'
import { PageLoader } from '@/components/ui/feedback'
import { Page } from '@/components/ui/page'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import {
  Select, SelectTrigger, SelectValue, SelectContent, SelectItem,
} from '@/components/ui/select'

// ── Profile tab (avatar, name, e-mail) ─────────────────────────
function ProfileTab({ user }) {
  const { t } = useTranslation('account')
  const updateAccount = useUpdateAccount()
  const updateAvatar = useUpdateAvatar()
  const requestEmail = useRequestEmailChange()

  const [name, setName] = useState(user?.name || '')
  const [avatarFile, setAvatarFile] = useState(null)
  const avatarPreview = avatarFile ? URL.createObjectURL(avatarFile) : user?.avatar_url

  const [editingEmail, setEditingEmail] = useState(false)
  const [newEmail, setNewEmail] = useState('')
  const [emailPassword, setEmailPassword] = useState('')

  const saveProfile = (e) => {
    e.preventDefault()
    if (name !== (user?.name || '')) updateAccount.mutate({ name })
    if (avatarFile) updateAvatar.mutate(avatarFile, { onSuccess: () => setAvatarFile(null) })
  }

  const submitEmail = (e) => {
    e.preventDefault()
    if (!newEmail.trim() || !emailPassword) return
    requestEmail.mutate({ email: newEmail.trim(), password: emailPassword }, {
      onSuccess: () => { setEditingEmail(false); setNewEmail(''); setEmailPassword('') },
    })
  }

  const savingProfile = updateAccount.isPending || updateAvatar.isPending
  const dirty = name !== (user?.name || '') || !!avatarFile

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
      <form onSubmit={saveProfile} className="space-y-6 lg:col-span-2">
        <Card>
          <CardHeader>
            <CardTitle>{t('profile.title')}</CardTitle>
            <CardDescription>{t('profile.description')}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-5">
            <div className="flex items-center gap-4">
              <div className="relative">
                <Avatar name={user?.name || user?.email} src={avatarPreview} size={72} />
                <label className="absolute -bottom-1 -right-1 grid size-7 cursor-pointer place-items-center rounded-full bg-brand text-white shadow ring-2 ring-surface transition hover:bg-brand/90">
                  <Camera size={14} />
                  <input type="file" accept="image/*" className="hidden" onChange={(e) => setAvatarFile(e.target.files?.[0] || null)} />
                </label>
              </div>
              <div className="min-w-0">
                <p className="text-sm font-semibold text-ink">{avatarFile ? avatarFile.name : t('profile.avatarLabel')}</p>
                <p className="text-xs text-ink-faint">{t('profile.avatarHint')}</p>
              </div>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="ac-name">{t('profile.nameLabel')}</Label>
              <Input id="ac-name" value={name} onChange={(e) => setName(e.target.value)} placeholder={t('profile.namePlaceholder')} />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Languages size={18} /> {t('language.title')}</CardTitle>
            <CardDescription>{t('language.description')}</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-1.5">
              <Label htmlFor="ac-locale">{t('language.label')}</Label>
              <Select
                value={user?.locale || 'pt-BR'}
                onValueChange={(locale) => updateAccount.mutate({ locale })}
              >
                <SelectTrigger id="ac-locale" className="w-full sm:w-72"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="pt-BR">{t('language.ptBR')}</SelectItem>
                  <SelectItem value="en">{t('language.en')}</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </CardContent>
        </Card>

        <div className="flex justify-end">
          <Button type="submit" size="lg" disabled={savingProfile || !dirty}>
            <Save size={18} /> {savingProfile ? t('profile.saving') : t('profile.save')}
          </Button>
        </div>
      </form>

      {/* E-mail */}
      <div className="lg:col-span-1">
        <Card className="h-fit">
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Mail size={18} /> {t('email.title')}</CardTitle>
            <CardDescription>{t('email.description')}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="rounded-xl border border-border bg-surface-muted/50 p-3">
              <p className="break-all text-sm font-semibold text-ink">{user?.email}</p>
              <p className="mt-0.5 flex items-center gap-1 text-xs">
                {user?.email_confirmed
                  ? <><Check size={12} className="text-emerald" /> <span className="text-ink-faint">{t('email.confirmed')}</span></>
                  : <><AlertCircle size={12} className="text-amber" /> <span className="text-ink-faint">{t('email.unconfirmed')}</span></>}
              </p>
            </div>

            {user?.pending_email && (
              <div className="flex items-start gap-2 rounded-xl border border-amber/30 bg-amber/8 p-3">
                <AlertCircle size={15} className="mt-0.5 shrink-0 text-amber" />
                <p className="text-xs text-ink-muted">
                  <Trans t={t} i18nKey="email.pendingNotice" values={{ email: user.pending_email }} components={{ strong: <strong className="break-all" /> }} />
                </p>
              </div>
            )}

            {editingEmail ? (
              <form onSubmit={submitEmail} className="space-y-3">
                <div className="space-y-1.5">
                  <Label htmlFor="ac-newemail">{t('email.newLabel')}</Label>
                  <Input id="ac-newemail" type="email" value={newEmail} onChange={(e) => setNewEmail(e.target.value)} placeholder={t('email.newPlaceholder')} />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="ac-emailpass">{t('email.currentPasswordLabel')}</Label>
                  <Input id="ac-emailpass" type="password" value={emailPassword} onChange={(e) => setEmailPassword(e.target.value)} placeholder="••••••••" autoComplete="current-password" />
                </div>
                <div className="flex gap-2">
                  <Button type="submit" size="sm" disabled={requestEmail.isPending}>
                    {requestEmail.isPending ? t('email.sending') : t('email.sendConfirmation')}
                  </Button>
                  <Button type="button" variant="ghost" size="sm" onClick={() => setEditingEmail(false)}>{t('email.cancel')}</Button>
                </div>
                <p className="text-xs text-ink-faint">{t('email.confirmationHint')}</p>
              </form>
            ) : (
              <Button type="button" variant="outline" size="sm" onClick={() => setEditingEmail(true)}>
                <Mail size={15} /> {t('email.change')}
              </Button>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

// ── Security tab (password) ────────────────────────────────────
function SecurityTab() {
  const { t } = useTranslation('account')
  const updatePassword = useUpdatePassword()
  const [form, setForm] = useState({ current_password: '', password: '', confirm: '' })
  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }))

  const mismatch = form.confirm.length > 0 && form.password !== form.confirm
  const tooShort = form.password.length > 0 && form.password.length < 8
  const canSubmit = form.current_password && form.password.length >= 8 && form.password === form.confirm

  const submit = (e) => {
    e.preventDefault()
    if (!canSubmit) return
    updatePassword.mutate(
      { current_password: form.current_password, password: form.password },
      { onSuccess: () => setForm({ current_password: '', password: '', confirm: '' }) },
    )
  }

  return (
    <div className="max-w-xl">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><KeyRound size={18} /> {t('security.title')}</CardTitle>
          <CardDescription>{t('security.description')}</CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={submit} className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="pw-current">{t('security.currentLabel')}</Label>
              <Input id="pw-current" type="password" value={form.current_password} onChange={set('current_password')} autoComplete="current-password" placeholder="••••••••" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="pw-new">{t('security.newLabel')}</Label>
              <Input id="pw-new" type="password" value={form.password} onChange={set('password')} autoComplete="new-password" placeholder="••••••••" />
              {tooShort && <p className="text-xs text-danger">{t('security.tooShort')}</p>}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="pw-confirm">{t('security.confirmLabel')}</Label>
              <Input id="pw-confirm" type="password" value={form.confirm} onChange={set('confirm')} autoComplete="new-password" placeholder="••••••••" />
              {mismatch && <p className="text-xs text-danger">{t('security.mismatch')}</p>}
            </div>
            <div className="flex justify-end">
              <Button type="submit" disabled={!canSubmit || updatePassword.isPending}>
                <Shield size={16} /> {updatePassword.isPending ? t('security.saving') : t('security.submit')}
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}

// ── Connections tab (Claude connector + OAuth apps) — personal ──
// Google Calendar is personal: meetings you schedule live on YOUR calendar
// (with the Meet link), so each member connects their own account here.
function GoogleCalendarCard() {
  const { t } = useTranslation('account')
  const { data: me } = useCurrentUser()
  const calendar = useGoogleCalendarMutations()
  const confirm = useConfirm()
  const connected = !!me?.user?.google_calendar_connected

  const onDisconnect = async () => {
    const ok = await confirm({
      title: t('calendar.disconnectConfirm.title'),
      description: t('calendar.disconnectConfirm.description'),
      confirmLabel: t('calendar.disconnectConfirm.confirm'),
      destructive: true,
    })
    if (ok) calendar.disconnect.mutate()
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2"><Calendar size={18} /> Google Calendar</CardTitle>
        <CardDescription>
          <Trans t={t} i18nKey="calendar.description" components={{ strong: <strong /> }} />
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-wrap items-center justify-between gap-3">
        {connected ? (
          <>
            <Badge variant="success" className="gap-1.5"><Check size={13} /> {t('calendar.connected')}</Badge>
            <Button
              type="button"
              variant="outline"
              onClick={onDisconnect}
              disabled={calendar.disconnect.isPending}
            >
              {calendar.disconnect.isPending ? t('calendar.disconnecting') : t('calendar.disconnect')}
            </Button>
          </>
        ) : (
          <>
            <p className="text-sm text-ink-muted">{t('calendar.notConnected')}</p>
            <Button
              type="button"
              onClick={() => calendar.connect.mutate()}
              disabled={calendar.connect.isPending}
            >
              <Calendar size={16} /> {calendar.connect.isPending ? t('calendar.opening') : t('calendar.connect')}
            </Button>
          </>
        )}
      </CardContent>
    </Card>
  )
}

function ConnectionsTab() {
  const { t } = useTranslation('account')
  const { data: connections, isLoading } = useConnections()
  const revoke = useRevokeConnection()
  const { data: connector, isLoading: loadingConnector } = useMcpConnector()
  const rotate = useRotateMcpConnector()
  const confirm = useConfirm()
  const navigate = useNavigate()
  const [copied, copy] = useCopyToClipboard(1500)
  const [revealed, setRevealed] = useState(false)
  // The connector unlocks once the user has ANY Agência+ workspace with an
  // active subscription; otherwise we show an upgrade hook.
  const locked = connector && connector.enabled === false
  const url = connector?.url || ''
  const masked = url.replace(/\/mcp\/c\/.+$/, '/mcp/c/••••••••••••')

  const onRotate = async () => {
    const ok = await confirm({
      title: t('connector.rotateConfirm.title'),
      description: t('connector.rotateConfirm.description'),
      confirmLabel: t('connector.rotateConfirm.confirm'),
      destructive: true,
    })
    if (ok) rotate.mutate()
  }

  const onRevoke = async (connection) => {
    const ok = await confirm({
      title: t('apps.revokeConfirm.title', { name: connection.name }),
      description: t('apps.revokeConfirm.description'),
      confirmLabel: t('apps.revokeConfirm.confirm'),
      destructive: true,
    })
    if (ok) revoke.mutate(connection.id)
  }

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
      <div className="space-y-6 lg:col-span-2">
        <GoogleCalendarCard />

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Bot size={18} /> {t('connector.title')}</CardTitle>
            <CardDescription>
              <Trans t={t} i18nKey="connector.description" components={{ strong: <strong /> }} />
            </CardDescription>
          </CardHeader>
          {locked ? (
            <CardContent className="space-y-3">
              <div className="flex items-start gap-3 rounded-xl border border-brand/30 bg-brand-soft/40 p-4">
                <span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-brand/15 text-brand"><Sparkles size={18} /></span>
                <div>
                  <p className="text-sm font-semibold text-ink">{t('connector.lockedTitle')}</p>
                  <p className="mt-0.5 text-sm text-ink-muted">{t('connector.lockedDescription')}</p>
                </div>
              </div>
              <Button type="button" onClick={() => navigate('/assinatura')}>
                <Sparkles size={16} /> {t('connector.seePlans')}
              </Button>
            </CardContent>
          ) : (
            <CardContent className="space-y-2.5">
              <Label>{t('connector.urlLabel')}</Label>
              <div className="flex flex-wrap items-center gap-2">
                <Input
                  readOnly
                  value={loadingConnector ? t('connector.loading') : (revealed ? url : masked)}
                  className="min-w-0 flex-1 font-mono text-sm"
                  onFocus={(e) => e.target.select()}
                />
                <Button type="button" variant="outline" onClick={() => setRevealed((v) => !v)}>
                  {revealed ? t('connector.hide') : t('connector.reveal')}
                </Button>
                <Button type="button" variant="outline" onClick={() => copy(url)} disabled={!url}>
                  {copied ? <Check size={16} /> : <Copy size={16} />} {copied ? t('connector.copied') : t('connector.copy')}
                </Button>
              </div>
              <div className="flex items-center justify-between gap-2 pt-1">
                <p className="text-xs text-ink-faint">{t('connector.secretHint')}</p>
                <Button type="button" variant="ghost" size="sm" className="shrink-0 text-ink-muted" onClick={onRotate} disabled={rotate.isPending}>
                  <RefreshCw size={14} /> {t('connector.rotate')}
                </Button>
              </div>
            </CardContent>
          )}
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><ShieldCheck size={18} /> {t('apps.title')}</CardTitle>
            <CardDescription>{t('apps.description')}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            {isLoading ? (
              <p className="text-sm text-ink-faint">{t('apps.loading')}</p>
            ) : !connections?.length ? (
              <p className="text-sm text-ink-faint">{t('apps.empty')}</p>
            ) : (
              connections.map((c) => (
                <div key={c.id} className="flex items-center justify-between rounded-lg border border-line p-3">
                  <div className="space-y-1.5">
                    <div className="flex items-center gap-2 font-semibold">
                      {c.name}
                      {c.dynamically_registered && <Badge variant="muted">auto</Badge>}
                    </div>
                    <div className="flex flex-wrap gap-1">
                      {c.scopes.map((s) => <Badge key={s} variant="outline">{s}</Badge>)}
                    </div>
                  </div>
                  <Button type="button" variant="ghost" className="text-danger" onClick={() => onRevoke(c)} disabled={revoke.isPending}>
                    <Trash2 size={16} /> {t('apps.revoke')}
                  </Button>
                </div>
              ))
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

// Each tab is its own URL (Portuguese segment); "profile" is the base path.
const TAB_TO_SEG = { profile: '', security: 'seguranca', connections: 'conexoes' }
const SEG_TO_TAB = { seguranca: 'security', conexoes: 'connections' }

export default function AccountIndex() {
  const { t } = useTranslation('account')
  const { tab: seg } = useParams()
  const navigate = useNavigate()
  const { data: me, isLoading } = useCurrentUser()

  const tab = SEG_TO_TAB[seg] || 'profile'
  const setTab = (value) => {
    const s = TAB_TO_SEG[value] || ''
    navigate(`/conta${s ? `/${s}` : ''}`, { replace: true })
  }

  if (isLoading) return <PageLoader />

  const user = me?.user

  return (
    <Page>
      <PageHeader
        eyebrow={t('header.eyebrow')}
        title={t('header.title')}
        icon={UserRound}
        color="#6366F1"
        description={t('header.description')}
      />

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList className="mb-6">
          <TabsTrigger value="profile"><UserRound size={15} /> {t('tabs.profile')}</TabsTrigger>
          <TabsTrigger value="security"><Shield size={15} /> {t('tabs.security')}</TabsTrigger>
          <TabsTrigger value="connections"><Bot size={15} /> {t('tabs.connections')}</TabsTrigger>
        </TabsList>

        <TabsContent value="profile" className="animate-rise">
          <ProfileTab key={user?.id} user={user} />
        </TabsContent>
        <TabsContent value="security" className="animate-rise">
          <SecurityTab />
        </TabsContent>
        <TabsContent value="connections" className="animate-rise">
          <ConnectionsTab />
        </TabsContent>
      </Tabs>
    </Page>
  )
}
