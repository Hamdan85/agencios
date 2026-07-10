import { useState } from 'react'
import { Link, useParams, useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import i18n from '@/i18n'
import {
  ArrowLeft, Mail, Phone, FileText, FolderKanban, Receipt, Wallet,
  Building2, StickyNote, Pencil, Plus, ListChecks, Sparkles, Palette, AtSign,
  Plug, Link2, Check, RefreshCw, Unplug, Copy, Share2, Video, BarChart3, Eye,
} from 'lucide-react'
import { toast } from 'sonner'
import { socialApi } from '@/api'
import {
  useClient, useClientMutations, useSocialAccountMutations, useMeetings, useMeetingMutations,
} from '@/hooks/useData'
import { useCurrentUser } from '@/hooks/useAuth'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { Button } from '@/components/ui/button'
import { useCopyToClipboard } from '@/components/ui/copy-button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { Badge, ColorBadge } from '@/components/ui/badge'
import { IconTile } from '@/components/ui/icon-tile'
import { Avatar } from '@/components/ui/avatar'
import { Card } from '@/components/ui/card'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import { Page } from '@/components/ui/page'
import ClientEditDialog from '@/components/client/ClientEditDialog'
import { CAROUSEL_STYLE_LABEL } from '@/components/client/positioningFields'
import { CarouselSlide, CarouselExampleDialog, buildExampleSlides } from '@/components/client/CarouselExample'
import { MeetingCard } from '@/components/meeting/MeetingCard'
import { MeetingFormDialog } from '@/components/meeting/MeetingFormDialog'
import { POSITIONING_FIELDS, CHANNEL_META } from '@/lib/constants'
import { brl, date } from '@/lib/formatters'
import { cn } from '@/lib/utils'

// Labels resolve lazily (getters) so they follow the active locale — same
// pattern as the label maps in lib/constants.
const tr = (key) => i18n.t(`clients:${key}`)
const PROJECT_STATUS = {
  active: { get label() { return tr('projectStatus.active') }, variant: 'success' },
  paused: { get label() { return tr('projectStatus.paused') }, variant: 'warning' },
  archived: { get label() { return tr('projectStatus.archived') }, variant: 'muted' },
}
const INVOICE_STATUS = {
  draft: { get label() { return tr('invoiceStatus.draft') }, variant: 'muted' },
  open: { get label() { return tr('invoiceStatus.open') }, variant: 'default' },
  paid: { get label() { return tr('invoiceStatus.paid') }, variant: 'success' },
  overdue: { get label() { return tr('invoiceStatus.overdue') }, variant: 'danger' },
  canceled: { get label() { return tr('invoiceStatus.canceled') }, variant: 'muted' },
}

function ContactChip({ icon: Icon, value, mono }) {
  if (!value) return null
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full bg-surface-muted px-3 py-1.5 text-sm font-medium text-ink-secondary">
      <Icon size={14} className="text-brand" />
      <span className={cn(mono && 'font-mono text-xs')}>{value}</span>
    </span>
  )
}

// ── Section header ──────────────────────────────────────────────
function SectionHead({ icon: Icon, color, title, onEdit }) {
  const { t } = useTranslation('clients')
  return (
    <div className="mb-3 flex items-center gap-2">
      <Icon size={18} style={{ color }} />
      <h2 className="font-display text-lg font-bold text-ink">{title}</h2>
      {onEdit && (
        <Button variant="ghost" size="sm" className="ml-auto text-ink-muted" onClick={onEdit}>
          <Pencil size={14} /> {t('actions.edit')}
        </Button>
      )}
    </div>
  )
}

// ── Brand identity (voice + @handle + colors + logo/avatar) ──────
function BrandIdentitySection({ client, onEdit }) {
  const { t } = useTranslation('clients')
  const has = client.has_brand
  const [exampleOpen, setExampleOpen] = useState(false)
  const swatch = (label, color) => (
    <div className="flex items-center gap-2">
      <span className="size-7 rounded-lg ring-1 ring-border" style={{ background: color }} />
      <div>
        <p className="text-xs font-bold uppercase tracking-wider text-ink-faint">{label}</p>
        <p className="font-mono text-xs text-ink-secondary">{color}</p>
      </div>
    </div>
  )

  return (
    <section className="mb-8">
      <SectionHead icon={Palette} color="#7C3AED" title={t('brand.title')} onEdit={onEdit} />
      {!has ? (
        <EmptyState
          icon={Palette}
          color="#7C3AED"
          title={t('brand.emptyTitle')}
          description={t('brand.emptyDescription')}
          action={<Button onClick={onEdit}><Palette size={16} /> {t('brand.define')}</Button>}
        />
      ) : (
        <Card className="space-y-5 p-6">
          <div className="flex flex-wrap items-center gap-5">
            {client.logo_url && (
              <div>
                <p className="mb-1.5 text-xs font-bold uppercase tracking-wider text-ink-faint">Logo</p>
                <div className="grid size-16 place-items-center overflow-hidden rounded-xl bg-surface-muted ring-1 ring-border">
                  <img src={client.logo_url} alt="Logo" className="size-full object-contain" />
                </div>
              </div>
            )}
            {client.default_creator_avatar_url && (
              <div>
                <p className="mb-1.5 text-xs font-bold uppercase tracking-wider text-ink-faint">{t('brand.ugcAvatar')}</p>
                <Avatar name="Avatar" src={client.default_creator_avatar_url} size={64} className="ring-1 ring-border" />
              </div>
            )}
            {client.default_handle && (
              <div>
                <p className="mb-1.5 text-xs font-bold uppercase tracking-wider text-ink-faint">@handle</p>
                <p className="inline-flex items-center gap-1 font-display text-base font-bold text-ink">
                  <AtSign size={15} className="text-brand" />{String(client.default_handle).replace(/^@/, '')}
                </p>
              </div>
            )}
          </div>
          <div className="flex flex-wrap gap-6">
            {swatch(t('brand.primaryColor'), client.brand_primary_color)}
            {swatch(t('brand.secondaryColor'), client.brand_secondary_color)}
          </div>
          <div>
            <p className="mb-1.5 text-xs font-bold uppercase tracking-wider text-ink-faint">{t('brand.carousel')}</p>
            <button
              type="button"
              onClick={() => setExampleOpen(true)}
              className="group flex w-full items-center gap-4 rounded-2xl border border-border bg-surface-muted/30 p-3 text-left transition hover:border-brand/40 hover:bg-brand-soft/30"
            >
              <div className="w-32 shrink-0">
                {/* A real slide 1 (the hook), rendered exactly as it's generated. */}
                <CarouselSlide slide={buildExampleSlides(client)[0]} index={1} total={5} client={client} />
              </div>
              <div className="min-w-0">
                <p className="font-display text-sm font-bold text-ink">
                  {CAROUSEL_STYLE_LABEL[client.carousel_style] || CAROUSEL_STYLE_LABEL.gradient}
                </p>
                <p className="mt-0.5 text-xs text-ink-muted">{t('brand.carouselHint')}</p>
                <span className="mt-2 inline-flex items-center gap-1 text-xs font-bold text-brand">
                  <Eye size={13} /> {t('brand.seeFullExample')}
                </span>
              </div>
            </button>
          </div>
          {client.brand_voice && (
            <div>
              <p className="text-xs font-bold uppercase tracking-wider text-ink-faint">{t('brand.voice')}</p>
              <p className="mt-1 text-sm leading-relaxed text-ink-secondary">{client.brand_voice}</p>
            </div>
          )}
        </Card>
      )}
      <CarouselExampleDialog client={client} open={exampleOpen} onOpenChange={setExampleOpen} />
    </section>
  )
}

// ── Positioning read view ───────────────────────────────────────
function PositioningSection({ client, onEdit }) {
  const { t } = useTranslation('clients')
  const positioning = client.positioning || {}
  const has = client.has_positioning
  const filled = POSITIONING_FIELDS.filter((f) => {
    const v = positioning[f.key]
    return Array.isArray(v) ? v.length > 0 : !!v
  })

  return (
    <section className="mb-2">
      <SectionHead icon={Sparkles} color="#6366F1" title={t('positioningSection.title')} onEdit={has ? onEdit : null} />
      {!has ? (
        <EmptyState
          icon={Sparkles}
          color="#6366F1"
          title={t('positioningSection.emptyTitle')}
          description={t('positioningSection.emptyDescription')}
          action={<Button onClick={onEdit}><Sparkles size={16} /> {t('positioningSection.define')}</Button>}
        />
      ) : (
        <Card className="space-y-5 p-6">
          {positioning.statement && (
            <p className="border-l-2 border-indigo pl-4 text-[15px] font-medium leading-relaxed text-ink-secondary">
              {positioning.statement}
            </p>
          )}
          <div className="grid grid-cols-1 gap-x-8 gap-y-4 sm:grid-cols-2">
            {filled.map((f) => {
              const v = positioning[f.key]
              return (
                <div key={f.key}>
                  <p className="text-xs font-bold uppercase tracking-wider text-ink-faint">{f.label}</p>
                  {f.type === 'pillars' ? (
                    <div className="mt-1.5 flex flex-wrap gap-1.5">
                      {v.map((p, i) => (
                        <ColorBadge key={i} color="#6366F1" tint="14" className="py-1 font-semibold">{p}</ColorBadge>
                      ))}
                    </div>
                  ) : (
                    <p className="mt-1 text-sm text-ink-secondary">{v}</p>
                  )}
                </div>
              )
            })}
          </div>
        </Card>
      )}
    </section>
  )
}

// ── Social networks (connected per client) ──────────────────────
function SocialCard({ provider, account, mutations }) {
  const { t } = useTranslation('clients')
  const meta = CHANNEL_META[provider]
  const confirm = useConfirm()
  if (!meta) return null
  const Icon = meta.icon
  const connected = !!account && account.status === 'connected' && !account.token_expired
  const needsReauth = !!account && (account.status === 'needs_reauth' || account.token_expired)
  const busy = mutations.connecting || mutations.disconnect.isPending

  const handleDisconnect = async () => {
    const ok = await confirm({
      title: t('social.disconnectConfirm.title', { network: meta.label }),
      description: t('social.disconnectConfirm.description'),
      confirmLabel: t('social.disconnect'),
      destructive: true,
    })
    if (ok) mutations.disconnect.mutate(account.id)
  }

  return (
    <Card className="flex flex-col p-5">
      <div className="flex items-start justify-between gap-2">
        <IconTile icon={Icon} color={meta.color} iconSize={22} className="size-11 rounded-xl" />
        {connected ? (
          <Badge variant="success"><Check size={12} /> {t('social.connected')}</Badge>
        ) : needsReauth ? (
          <Badge variant="warning"><RefreshCw size={12} /> {t('social.reauth')}</Badge>
        ) : (
          <Badge variant="muted">{t('social.disconnected')}</Badge>
        )}
      </div>
      <h3 className="mt-3 font-display text-base font-bold text-ink">{meta.label}</h3>
      <p className="mt-0.5 min-h-5 truncate text-sm text-ink-muted">
        {connected ? `@${account.username || ''}` : needsReauth ? t('social.sessionExpired') : t('social.connectPrompt')}
      </p>
      <div className="mt-4 flex gap-2">
        {connected ? (
          <Button variant="outline" size="sm" className="w-full" disabled={busy} onClick={handleDisconnect}>
            <Unplug size={15} /> {t('social.disconnect')}
          </Button>
        ) : (
          <Button variant="solid" size="sm" className="w-full" disabled={busy} onClick={() => mutations.connect(provider)}>
            {needsReauth ? <><RefreshCw size={15} /> {t('social.reconnect')}</> : <><Link2 size={15} /> {t('social.connect')}</>}
          </Button>
        )}
      </div>
    </Card>
  )
}

// ── Client portal link (login-less client central) ──────────────
function PortalLinkSection({ client, mutation }) {
  const { t } = useTranslation('clients')
  const [, copyToClipboard] = useCopyToClipboard()
  const confirm = useConfirm()
  const url = client.portal_url

  async function copyLink() {
    if (!(await copyToClipboard(url))) {
      toast.error(t('portal.copyError'))
      return
    }
    toast.success(t('portal.copySuccess'))
  }

  async function rotate() {
    const ok = await confirm({
      title: t('portal.rotateConfirm.title'),
      description: t('portal.rotateConfirm.description'),
      confirmLabel: t('portal.rotateConfirm.confirm'),
      destructive: true,
    })
    if (ok) mutation.mutate(client.id)
  }

  return (
    <section className="mb-8">
      <SectionHead icon={Share2} color="var(--ag-brand, #7C3AED)" title={t('portal.title')} />
      <Card className="mt-1">
        <div className="flex flex-col gap-4 p-4">
          <div className="flex items-center gap-3">
            <div
              className="grid size-10 shrink-0 place-items-center rounded-xl text-white"
              style={{ background: 'var(--ag-brand, #7C3AED)' }}
            >
              <Link2 size={18} />
            </div>
            <div>
              <p className="font-semibold text-ink">{t('portal.linkTitle')}</p>
              <p className="text-sm text-ink-muted">
                {t('portal.linkDescription')}
              </p>
            </div>
          </div>
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
            <input
              readOnly
              value={url || ''}
              onFocus={(e) => e.target.select()}
              className="min-w-0 flex-1 truncate rounded-xl border border-border bg-surface-muted px-3 py-2 font-mono text-sm text-ink-secondary"
            />
            <div className="flex gap-2">
              <Button variant="solid" onClick={copyLink} className="shrink-0">
                <Copy size={15} /> {t('portal.copy')}
              </Button>
              <Button variant="outline" onClick={rotate} disabled={mutation.isPending} className="shrink-0">
                <RefreshCw size={15} className={cn(mutation.isPending && 'animate-spin')} /> {t('portal.rotate')}
              </Button>
            </div>
          </div>
        </div>
      </Card>
    </section>
  )
}

function SocialSection({ clientId, accounts }) {
  const { t } = useTranslation('clients')
  const mutations = useSocialAccountMutations(clientId)
  const [linking, setLinking] = useState(false)
  const [, copyToClipboard] = useCopyToClipboard()
  // One card per network. A client may have several accounts on the same network
  // (one active, others revoked from earlier), so prefer the connected one.
  const byProvider = {}
  for (const a of accounts || []) {
    const cur = byProvider[a.provider]
    if (!cur || a.status === 'connected') byProvider[a.provider] = a
  }

  async function copyConnectLink() {
    setLinking(true)
    try {
      const { url } = await socialApi.connectLink(clientId)
      if (!(await copyToClipboard(url))) throw new Error('clipboard unavailable')
      toast.success(t('social.connectLinkCopied'))
    } catch {
      toast.error(t('social.connectLinkError'))
    } finally {
      setLinking(false)
    }
  }

  return (
    <section>
      <SectionHead icon={Plug} color="var(--ag-brand, #7C3AED)" title={t('social.title')} />

      {/* Banner: send the login-less self-serve link to the client. */}
      <Card className="mb-5 mt-1">
        <div className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-3">
            <div
              className="grid size-10 shrink-0 place-items-center rounded-xl text-white"
              style={{ background: 'var(--ag-brand, #7C3AED)' }}
            >
              <Share2 size={18} />
            </div>
            <div>
              <p className="font-semibold text-ink">{t('social.selfServeTitle')}</p>
              <p className="text-sm text-ink-muted">
                {t('social.selfServeDescription')}
              </p>
            </div>
          </div>
          <Button variant="solid" disabled={linking} onClick={copyConnectLink} className="shrink-0">
            <Copy size={15} /> {t('social.copyConnectLink')}
          </Button>
        </div>
      </Card>

      <p className="mb-4 max-w-2xl text-sm text-ink-muted">
        {t('social.manualHint')}
      </p>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {Object.keys(CHANNEL_META).map((provider) => (
          <SocialCard key={provider} provider={provider} account={byProvider[provider]} mutations={mutations} />
        ))}
      </div>
    </section>
  )
}

// ── Projects ────────────────────────────────────────────────────
function ProjectsSection({ projects }) {
  const { t } = useTranslation('clients')
  return (
    <section>
      <SectionHead icon={FolderKanban} color="#10B981" title={t('projects.title')} />
      {projects.length === 0 ? (
        <EmptyState
          icon={FolderKanban}
          color="#10B981"
          title={t('projects.emptyTitle')}
          description={t('projects.emptyDescription')}
          action={<Button asChild variant="outline"><Link to="/campanhas"><Plus size={16} /> {t('projects.newProject')}</Link></Button>}
        />
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {projects.map((p) => {
            const color = p.color || '#7C3AED'
            const st = PROJECT_STATUS[p.status] || PROJECT_STATUS.active
            return (
              <Link key={p.id} to={`/campanhas/${p.id}`} className="group relative flex flex-col overflow-hidden rounded-2xl border border-border bg-surface lift">
                <div className="h-1.5 w-full" style={{ background: color }} />
                <div className="flex flex-1 flex-col p-4">
                  <div className="flex items-start justify-between gap-2">
                    <h3 className="font-display text-base font-bold text-ink">{p.name}</h3>
                    <Badge variant={st.variant}>{st.label}</Badge>
                  </div>
                  <ColorBadge color={color} tint="14" className="mt-3 w-fit py-1">
                    <ListChecks size={13} /> {p.tickets_count ?? 0} tickets
                  </ColorBadge>
                </div>
              </Link>
            )
          })}
        </div>
      )}
    </section>
  )
}

// ── Invoices ────────────────────────────────────────────────────
function InvoicesSection({ invoices }) {
  const { t } = useTranslation('clients')
  return (
    <section>
      <SectionHead icon={Receipt} color="#F97316" title={t('invoices.title')} />
      {invoices.length === 0 ? (
        <EmptyState
          icon={Receipt}
          color="#F97316"
          title={t('invoices.emptyTitle')}
          description={t('invoices.emptyDescription')}
          action={<Button asChild variant="outline"><Link to="/cobrancas"><Plus size={16} /> {t('invoices.newInvoice')}</Link></Button>}
        />
      ) : (
        <Card className="divide-y divide-border">
          {invoices.map((inv) => {
            const st = INVOICE_STATUS[inv.status] || INVOICE_STATUS.draft
            return (
              <div key={inv.id} className="flex items-center justify-between gap-3 p-4">
                <div className="flex min-w-0 items-center gap-3">
                  <div className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-orange/12 text-orange">
                    <Receipt size={18} />
                  </div>
                  <div className="min-w-0">
                    <p className="font-display text-base font-bold text-ink">{brl(inv.amount_cents)}</p>
                    {inv.description && <p className="truncate text-xs text-ink-muted">{inv.description}</p>}
                  </div>
                </div>
                <div className="flex shrink-0 flex-col items-end gap-1 sm:flex-row sm:items-center sm:gap-3">
                  <span className="whitespace-nowrap text-xs font-medium text-ink-muted">{t('invoices.due', { date: date(inv.due_date) })}</span>
                  <Badge variant={st.variant}>{st.label}</Badge>
                </div>
              </div>
            )
          })}
        </Card>
      )}
    </section>
  )
}

// ── Left column: basic client data ──────────────────────────────
function BasicColumn({ client, projects, invoices, totalPaid, archived, onEdit }) {
  const { t } = useTranslation('clients')
  return (
    <Card className="overflow-hidden lg:sticky lg:top-6">
      <div className="h-1.5 w-full bg-brand-gradient" />
      <div className="p-5">
        <div className="flex flex-col items-center text-center">
          <Avatar name={client.name} src={client.logo_url} size={72} ring />
          <h1 className="mt-3 font-display text-xl font-extrabold tracking-tight text-ink">{client.name || t('show.clientFallback')}</h1>
          <Badge className="mt-1.5" variant={archived ? 'muted' : 'success'}>{archived ? t('status.archived') : t('status.active')}</Badge>
          {client.company && (
            <p className="mt-1 flex items-center gap-1.5 text-sm font-medium text-ink-muted">
              <Building2 size={14} /> {client.company}
            </p>
          )}
          <Button variant="outline" size="sm" className="mt-4 w-full" onClick={onEdit}>
            <Pencil size={15} /> {t('show.editClient')}
          </Button>
          <Button asChild variant="outline" size="sm" className="mt-2 w-full">
            <Link to={`/publicacoes?client=${client.id}`}>
              <BarChart3 size={15} /> {t('show.viewPerformance')}
            </Link>
          </Button>
        </div>

        <div className="mt-5 flex flex-wrap justify-center gap-2">
          <ContactChip icon={Mail} value={client.email} />
          <ContactChip icon={Phone} value={client.phone} />
          <ContactChip icon={FileText} value={client.document} mono />
        </div>

        {client.notes && (
          <p className="mt-4 flex items-start gap-2 rounded-xl bg-surface-muted/60 p-3 text-sm text-ink-secondary">
            <StickyNote size={15} className="mt-0.5 shrink-0 text-amber" /> {client.notes}
          </p>
        )}

        <div className="mt-5 grid grid-cols-3 gap-2 border-t border-border pt-4 text-center">
          <Stat icon={FolderKanban} color="#10B981" label={t('show.stats.campaigns')} value={projects.length} />
          <Stat icon={Receipt} color="#F97316" label={t('show.stats.invoices')} value={invoices.length} />
          <Stat icon={Wallet} color="#7C3AED" label={t('show.stats.billed')} value={brl(totalPaid)} />
        </div>
      </div>
    </Card>
  )
}

function Stat({ icon: Icon, color, label, value }) {
  return (
    <div>
      <Icon size={16} className="mx-auto" style={{ color }} />
      <p className="mt-1 font-display text-sm font-extrabold text-ink">{value}</p>
      <p className="text-[11px] font-semibold text-ink-faint">{label}</p>
    </div>
  )
}

// Every meeting anyone on the team scheduled with this client — meetings are
// personal, so only the owner of each one can edit/cancel it; the owner chip
// shows who scheduled it.
function MeetingsSection({ client }) {
  const { t } = useTranslation('clients')
  const { data: meetings, isLoading } = useMeetings({ client_id: client.id })
  const { create, update, destroy } = useMeetingMutations()
  const { data: me } = useCurrentUser()
  const confirm = useConfirm()
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState(null)

  const myId = me?.user?.id
  const list = meetings || []
  const now = Date.now()
  const upcoming = list.filter((m) => new Date(m.starts_at).getTime() >= now)
  const past = list.filter((m) => new Date(m.starts_at).getTime() < now).reverse()

  const onEdit = (m) => { setEditing(m); setOpen(true) }
  const onCancel = async (m) => {
    const ok = await confirm({
      title: t('meetings.cancelConfirm.title', { title: m.title }),
      description: t('meetings.cancelConfirm.description'),
      confirmLabel: t('meetings.cancelConfirm.confirm'),
      cancelLabel: t('actions.back'),
      destructive: true,
    })
    if (ok) destroy.mutate(m.id)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm text-ink-muted">{t('meetings.description')}</p>
        <Button size="sm" onClick={() => { setEditing(null); setOpen(true) }}>
          <Plus size={16} /> {t('meetings.schedule')}
        </Button>
      </div>

      {isLoading ? (
        <p className="py-8 text-center text-sm text-ink-faint">{t('meetings.loading')}</p>
      ) : list.length === 0 ? (
        <EmptyState
          icon={Video}
          color="#14B8A6"
          title={t('meetings.emptyTitle')}
          description={t('meetings.emptyDescription')}
          action={<Button size="sm" onClick={() => { setEditing(null); setOpen(true) }}><Plus size={16} /> {t('meetings.schedule')}</Button>}
        />
      ) : (
        <div className="space-y-4">
          {[...upcoming, ...past].map((m) => (
            <MeetingCard
              key={m.id}
              meeting={m}
              past={new Date(m.starts_at).getTime() < now}
              canEdit={m.user_id === myId}
              showOwner
              onEdit={onEdit}
              onCancel={onCancel}
            />
          ))}
        </div>
      )}

      <MeetingFormDialog
        open={open}
        onOpenChange={setOpen}
        editing={editing}
        createMutation={create}
        updateMutation={update}
        defaultClient={{ id: client.id, name: client.name }}
      />
    </div>
  )
}

// Each tab is its own URL (Portuguese segment); "branding" is the base path.
const TAB_TO_SEG = { branding: '', config: 'configuracoes', projects: 'campanhas', invoices: 'faturas', meetings: 'reunioes' }
// `projetos` kept as a legacy alias — the entity was renamed to Campanha.
const SEG_TO_TAB = { configuracoes: 'config', campanhas: 'projects', projetos: 'projects', faturas: 'invoices', reunioes: 'meetings' }

export default function ClientShow() {
  const { t } = useTranslation('clients')
  const { id, tab: seg } = useParams()
  const navigate = useNavigate()
  const { data, isLoading } = useClient(id)
  const mutations = useClientMutations()
  const { rotatePortalLink } = mutations
  const [editorOpen, setEditorOpen] = useState(false)

  const tab = SEG_TO_TAB[seg] || 'branding'
  const setTab = (value) => {
    const s = TAB_TO_SEG[value] || ''
    navigate(`/clientes/${id}${s ? `/${s}` : ''}`, { replace: true })
  }

  if (isLoading) return <PageLoader />

  const client = data?.client || {}
  const projects = data?.projects || []
  const invoices = data?.invoices || []
  const socialAccounts = data?.social_accounts || []
  const archived = client.status === 'archived'

  const totalPaid = invoices
    .filter((i) => i.status === 'paid')
    .reduce((sum, i) => sum + (Number(i.amount_cents) || 0), 0)

  const openEditor = () => setEditorOpen(true)

  return (
    <Page>
      <Link to="/clientes" className="mb-5 inline-flex items-center gap-1.5 text-sm font-semibold text-ink-muted transition hover:text-brand">
        <ArrowLeft size={16} /> {t('index.title')}
      </Link>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[340px_1fr]">
        <BasicColumn
          client={client}
          projects={projects}
          invoices={invoices}
          totalPaid={totalPaid}
          archived={archived}
          onEdit={openEditor}
        />

        <Tabs value={tab} onValueChange={setTab}>
          <TabsList className="mb-5">
            <TabsTrigger value="branding"><Palette size={15} /> {t('show.tabs.branding')}</TabsTrigger>
            <TabsTrigger value="config"><Plug size={15} /> {t('show.tabs.config')}</TabsTrigger>
            <TabsTrigger value="projects"><FolderKanban size={15} /> {t('show.tabs.projects')}</TabsTrigger>
            <TabsTrigger value="meetings"><Video size={15} /> {t('show.tabs.meetings')}</TabsTrigger>
            <TabsTrigger value="invoices"><Receipt size={15} /> {t('show.tabs.invoices')}</TabsTrigger>
          </TabsList>

          <TabsContent value="branding" className="animate-rise">
            <BrandIdentitySection client={client} onEdit={openEditor} />
            <PositioningSection client={client} onEdit={openEditor} />
          </TabsContent>

          <TabsContent value="config" className="animate-rise">
            <PortalLinkSection client={client} mutation={rotatePortalLink} />
            <SocialSection clientId={id} accounts={socialAccounts} />
          </TabsContent>

          <TabsContent value="projects" className="animate-rise">
            <ProjectsSection projects={projects} />
          </TabsContent>

          <TabsContent value="meetings" className="animate-rise">
            <MeetingsSection client={client} />
          </TabsContent>

          <TabsContent value="invoices" className="animate-rise">
            <InvoicesSection invoices={invoices} />
          </TabsContent>
        </Tabs>
      </div>

      <ClientEditDialog
        open={editorOpen}
        onOpenChange={setEditorOpen}
        client={client}
        mutations={mutations}
      />
    </Page>
  )
}
