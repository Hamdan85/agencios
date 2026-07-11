import { useMemo, useState } from 'react'
import { useTranslation } from 'react-i18next'
import {
  Receipt, Plus, MoreHorizontal, Ban, Wallet, Link2, CheckCircle2,
  CircleDollarSign, AlertTriangle, FileText, ExternalLink, Hash, Send,
} from 'lucide-react'
import i18n from '@/i18n'
import { useInvoices, useInvoiceMutations, useSettings } from '@/hooks/useData'
import { PageHeader, StatCard } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { CopyButton } from '@/components/ui/copy-button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { IconTile } from '@/components/ui/icon-tile'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { Page } from '@/components/ui/page'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from '@/components/ui/dialog'
import { InvoiceFormDialog } from '@/components/billing/InvoiceFormDialog'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem,
} from '@/components/ui/dropdown-menu'
import {
  Tabs, TabsList, TabsTrigger,
} from '@/components/ui/tabs'
import { brl, date, relativeDay } from '@/lib/formatters'
import { cn } from '@/lib/utils'

const STATUS_META = {
  draft: { get label() { return i18n.t('invoices:status.draft') }, variant: 'muted', dot: '#94A3B8' },
  open: { get label() { return i18n.t('invoices:status.open') }, variant: 'default', dot: '#0EA5E9' },
  paid: { get label() { return i18n.t('invoices:status.paid') }, variant: 'success', dot: '#10B981' },
  overdue: { get label() { return i18n.t('invoices:status.overdue') }, variant: 'danger', dot: '#F43F5E' },
  canceled: { get label() { return i18n.t('invoices:status.canceled') }, variant: 'muted', dot: '#94A3B8' },
}
const statusMeta = (s) => STATUS_META[s] || STATUS_META.draft

const FILTERS = [
  { value: 'all', get label() { return i18n.t('invoices:filters.all') } },
  { value: 'open', get label() { return i18n.t('invoices:filters.open') } },
  { value: 'paid', get label() { return i18n.t('invoices:filters.paid') } },
  { value: 'overdue', get label() { return i18n.t('invoices:filters.overdue') } },
  { value: 'draft', get label() { return i18n.t('invoices:filters.draft') } },
  { value: 'canceled', get label() { return i18n.t('invoices:filters.canceled') } },
]

// ── Payment link dialog ────────────────────────────────────────
function PaymentLinkDialog({ invoice, open, onOpenChange, onSendPaymentLink, sending }) {
  const { t } = useTranslation('invoices')
  const charge = invoice?.charge
  const link = charge?.payment_link

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <IconTile icon={Link2} color="#0EA5E9" iconSize={22} className="mb-1 size-11" />
          <DialogTitle>{t('paymentDialog.title')}</DialogTitle>
          <DialogDescription>{invoice?.client_name ? t('paymentDialog.subtitle', { name: invoice.client_name }) : t('paymentDialog.subtitleFallback')}</DialogDescription>
        </DialogHeader>

        <div className="flex flex-col items-center gap-4">
          <p className="font-display text-3xl font-extrabold tracking-tight text-ink">
            {brl(charge?.amount_cents ?? invoice?.amount_cents)}
          </p>

          {link ? (
            <>
              <div className="w-full space-y-2">
                <Label>{t('paymentDialog.mpLink')}</Label>
                <div className="flex items-start gap-2 rounded-xl border border-border bg-surface-muted p-3">
                  <code className="max-h-24 flex-1 overflow-y-auto break-all font-mono text-xs text-ink-secondary no-scrollbar">{link}</code>
                </div>
              </div>

              <div className="flex w-full gap-2">
                <CopyButton value={link} label={t('paymentDialog.copyLink')} className="flex-1" />
                {onSendPaymentLink && (
                  <Button onClick={() => onSendPaymentLink(invoice)} disabled={sending} className="flex-1">
                    <Send size={16} /> {sending ? t('paymentDialog.sending') : t('paymentDialog.sendToClient')}
                  </Button>
                )}
              </div>

              <a href={link} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1.5 text-sm font-semibold text-brand hover:underline">
                {t('paymentDialog.openPage')} <ExternalLink size={14} />
              </a>

              <p className="text-center text-xs text-ink-muted">{t('paymentDialog.autoNote')}</p>
            </>
          ) : (
            <p className="rounded-xl bg-surface-muted px-4 py-6 text-center text-sm text-ink-muted">
              {t('paymentDialog.generating')}
            </p>
          )}
        </div>
      </DialogContent>
    </Dialog>
  )
}

// ── Invoice row ────────────────────────────────────────────────
function InvoiceRow({ invoice, onMarkPaid, onCancel, onGenerateLink, onShowLink, onSendPaymentLink, generating, sending, paymentLinksAvailable }) {
  const { t } = useTranslation('invoices')
  const m = statusMeta(invoice.status)
  const rel = relativeDay(invoice.due_date)
  const canAct = !['paid', 'canceled'].includes(invoice.status)
  const link = invoice.charge?.payment_link

  return (
    <div className="flex flex-wrap items-center justify-between gap-4 p-4 transition-colors hover:bg-surface-muted/40">
      <div className="flex min-w-0 items-center gap-3">
        <IconTile icon={Receipt} color={m.dot} tint="18" iconSize={20} className="size-11 rounded-xl" />
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <p className="truncate font-medium text-ink">
              {invoice.client_name || t('row.clientFallback')}
            </p>
            <Badge variant={m.variant}>{m.label}</Badge>
          </div>
          <div className="mt-0.5 flex flex-wrap items-center gap-2 text-xs text-ink-muted">
            {invoice.description && <span className="truncate">{invoice.description}</span>}
            {invoice.external_reference && (
              <span className="inline-flex items-center gap-1 font-mono">
                <Hash size={11} />{invoice.external_reference}
              </span>
            )}
          </div>
        </div>
      </div>

      <div className="flex items-center gap-4">
        <div className="text-right">
          <p className="font-display text-lg font-extrabold tracking-tight text-ink">{brl(invoice.amount_cents)}</p>
          {invoice.due_date && (
            <p className={cn('text-xs font-medium', rel?.tone === 'danger' ? 'text-danger' : 'text-ink-muted')}>
              {t('row.due', { date: date(invoice.due_date) })}{rel ? ` · ${rel.text}` : ''}
            </p>
          )}
        </div>

        {canAct && (link ? (
          <Button variant="outline" size="sm" onClick={() => onShowLink(invoice)}>
            <Link2 size={15} /> {t('row.paymentLink')}
          </Button>
        ) : (
          <Button variant="outline" size="sm" onClick={() => onGenerateLink(invoice)} disabled={generating}>
            <Link2 size={15} /> {generating ? t('row.generating') : t('row.generateLink')}
          </Button>
        ))}

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon-sm" className="text-ink-muted">
              <MoreHorizontal size={18} />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem disabled={!canAct} onSelect={() => canAct && onMarkPaid(invoice)}>
              <CheckCircle2 /> {t('row.markPaid')}
            </DropdownMenuItem>
            {canAct && (link ? (
              <DropdownMenuItem onSelect={() => onShowLink(invoice)}><Link2 /> {t('row.viewPaymentLink')}</DropdownMenuItem>
            ) : (
              <DropdownMenuItem onSelect={() => onGenerateLink(invoice)}><Link2 /> {t('row.generatePaymentLink')}</DropdownMenuItem>
            ))}
            {canAct && paymentLinksAvailable && (
              <DropdownMenuItem disabled={sending} onSelect={() => onSendPaymentLink(invoice)}>
                <Send /> {sending ? t('row.sending') : t('row.sendPaymentLink')}
              </DropdownMenuItem>
            )}
            <DropdownMenuItem
              disabled={!canAct}
              onSelect={() => canAct && onCancel(invoice)}
              className="text-danger data-[highlighted]:text-danger"
            >
              <Ban /> {t('row.cancel')}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  )
}

export default function InvoicesIndex() {
  const { t } = useTranslation('invoices')
  const { data: invoices, isLoading } = useInvoices()
  const { cancel, markPaid, paymentLink, sendPaymentLink } = useInvoiceMutations()
  const { data: settings } = useSettings()
  const paymentLinksAvailable = !!settings?.setting?.payment_links_available
  const confirm = useConfirm()
  const [createOpen, setCreateOpen] = useState(false)
  const [linkInvoiceId, setLinkInvoiceId] = useState(null)
  const [filter, setFilter] = useState('all')

  const list = invoices || []

  const stats = useMemo(() => {
    const sumBy = (pred) => list.filter(pred).reduce((s, i) => s + (Number(i.amount_cents) || 0), 0)
    return {
      open: sumBy((i) => i.status === 'open'),
      paid: sumBy((i) => i.status === 'paid'),
      overdueCount: list.filter((i) => i.status === 'overdue').length,
      overdueSum: sumBy((i) => i.status === 'overdue'),
    }
  }, [list])

  const filtered = useMemo(
    () => (filter === 'all' ? list : list.filter((i) => i.status === filter)),
    [list, filter],
  )

  const linkInvoice = list.find((i) => i.id === linkInvoiceId) || null
  const generatingId = paymentLink.isPending ? paymentLink.variables : null

  const onMarkPaid = async (inv) => {
    const ok = await confirm({
      title: t('confirm.markPaid.title'),
      description: t('confirm.markPaid.description'),
      confirmLabel: t('confirm.markPaid.confirm'),
      icon: CheckCircle2,
      tone: '#10B981',
    })
    if (ok) markPaid.mutate(inv.id)
  }
  const onCancel = async (inv) => {
    const ok = await confirm({
      title: t('confirm.cancel.title'),
      description: t('confirm.cancel.description'),
      confirmLabel: t('confirm.cancel.confirm'),
      cancelLabel: t('confirm.cancel.back'),
      destructive: true,
    })
    if (ok) cancel.mutate(inv.id)
  }
  const onGenerateLink = (inv) => paymentLink.mutate(inv.id, { onSuccess: () => setLinkInvoiceId(inv.id) })
  const onShowLink = (inv) => setLinkInvoiceId(inv.id)
  const onSendPaymentLink = (inv) => sendPaymentLink.mutate(inv.id)
  const sendingId = sendPaymentLink.isPending ? sendPaymentLink.variables : null

  if (isLoading) return <PageLoader />

  return (
    <Page>
      <PageHeader
        eyebrow={t('page.eyebrow')}
        title={t('page.title')}
        icon={Receipt}
        color="#F97316"
        description={t('page.description')}
        actions={<Button onClick={() => setCreateOpen(true)}><Plus size={18} /> {t('page.newInvoice')}</Button>}
      />

      <div className="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
        <StatCard label={t('stats.open.label')} value={brl(stats.open)} icon={CircleDollarSign} color="#0EA5E9" sub={t('stats.open.sub')} />
        <StatCard label={t('stats.paid.label')} value={brl(stats.paid)} icon={Wallet} color="#10B981" sub={t('stats.paid.sub')} />
        <StatCard label={t('stats.overdue.label')} value={stats.overdueCount} icon={AlertTriangle} color="#F43F5E" sub={brl(stats.overdueSum)} />
      </div>

      <div className="mb-5 overflow-x-auto no-scrollbar">
        <Tabs value={filter} onValueChange={setFilter}>
          <TabsList>
            {FILTERS.map((f) => <TabsTrigger key={f.value} value={f.value}>{f.label}</TabsTrigger>)}
          </TabsList>
        </Tabs>
      </div>

      {filtered.length === 0 ? (
        <EmptyState
          icon={FileText}
          color="#F97316"
          title={list.length === 0 ? t('empty.noneTitle') : t('empty.filteredTitle')}
          description={list.length === 0 ? t('empty.noneDescription') : t('empty.filteredDescription')}
          action={list.length === 0 ? <Button onClick={() => setCreateOpen(true)}><Plus size={18} /> {t('page.newInvoice')}</Button> : null}
        />
      ) : (
        <Card className="divide-y divide-border">
          {filtered.map((inv) => (
            <InvoiceRow
              key={inv.id}
              invoice={inv}
              onMarkPaid={onMarkPaid}
              onCancel={onCancel}
              onGenerateLink={onGenerateLink}
              onShowLink={onShowLink}
              onSendPaymentLink={onSendPaymentLink}
              generating={generatingId === inv.id}
              sending={sendingId === inv.id}
              paymentLinksAvailable={paymentLinksAvailable}
            />
          ))}
        </Card>
      )}

      <InvoiceFormDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
      />
      <PaymentLinkDialog
        invoice={linkInvoice}
        open={linkInvoiceId != null}
        onOpenChange={(v) => { if (!v) setLinkInvoiceId(null) }}
        onSendPaymentLink={paymentLinksAvailable ? onSendPaymentLink : null}
        sending={linkInvoice && sendingId === linkInvoice.id}
      />
    </Page>
  )
}
