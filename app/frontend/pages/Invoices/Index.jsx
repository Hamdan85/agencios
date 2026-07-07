import { useMemo, useState } from 'react'
import {
  Receipt, Plus, MoreHorizontal, Ban, Wallet, Link2, CheckCircle2,
  CircleDollarSign, AlertTriangle, FileText, ExternalLink, Hash, Send,
} from 'lucide-react'
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
  draft: { label: 'Rascunho', variant: 'muted', dot: '#94A3B8' },
  open: { label: 'Em aberto', variant: 'default', dot: '#0EA5E9' },
  paid: { label: 'Pago', variant: 'success', dot: '#10B981' },
  overdue: { label: 'Vencida', variant: 'danger', dot: '#F43F5E' },
  canceled: { label: 'Cancelada', variant: 'muted', dot: '#94A3B8' },
}
const statusMeta = (s) => STATUS_META[s] || STATUS_META.draft

const FILTERS = [
  { value: 'all', label: 'Todas' },
  { value: 'open', label: 'Em aberto' },
  { value: 'paid', label: 'Pagas' },
  { value: 'overdue', label: 'Vencidas' },
  { value: 'draft', label: 'Rascunhos' },
  { value: 'canceled', label: 'Canceladas' },
]

// ── Payment link dialog ────────────────────────────────────────
function PaymentLinkDialog({ invoice, open, onOpenChange, onSendPaymentLink, sending }) {
  const charge = invoice?.charge
  const link = charge?.payment_link

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <IconTile icon={Link2} color="#0EA5E9" iconSize={22} className="mb-1 size-11" />
          <DialogTitle>Link de pagamento</DialogTitle>
          <DialogDescription>{invoice?.client_name ? `Cobrança de ${invoice.client_name}` : 'Cobrança'}</DialogDescription>
        </DialogHeader>

        <div className="flex flex-col items-center gap-4">
          <p className="font-display text-3xl font-extrabold tracking-tight text-ink">
            {brl(charge?.amount_cents ?? invoice?.amount_cents)}
          </p>

          {link ? (
            <>
              <div className="w-full space-y-2">
                <Label>Link Mercado Pago</Label>
                <div className="flex items-start gap-2 rounded-xl border border-border bg-surface-muted p-3">
                  <code className="max-h-24 flex-1 overflow-y-auto break-all font-mono text-xs text-ink-secondary no-scrollbar">{link}</code>
                </div>
              </div>

              <div className="flex w-full gap-2">
                <CopyButton value={link} label="Copiar link" className="flex-1" />
                {onSendPaymentLink && (
                  <Button onClick={() => onSendPaymentLink(invoice)} disabled={sending} className="flex-1">
                    <Send size={16} /> {sending ? 'Enviando…' : 'Enviar ao cliente'}
                  </Button>
                )}
              </div>

              <a href={link} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1.5 text-sm font-semibold text-brand hover:underline">
                Abrir página de pagamento <ExternalLink size={14} />
              </a>

              <p className="text-center text-xs text-ink-muted">Ou envie o link acima ao cliente — a baixa é automática após o pagamento.</p>
            </>
          ) : (
            <p className="rounded-xl bg-surface-muted px-4 py-6 text-center text-sm text-ink-muted">
              Gerando o link de pagamento…
            </p>
          )}
        </div>
      </DialogContent>
    </Dialog>
  )
}

// ── Invoice row ────────────────────────────────────────────────
function InvoiceRow({ invoice, onMarkPaid, onCancel, onGenerateLink, onShowLink, onSendPaymentLink, generating, sending, paymentLinksAvailable }) {
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
              {invoice.client_name || 'Cliente'}
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
              Venc. {date(invoice.due_date)}{rel ? ` · ${rel.text}` : ''}
            </p>
          )}
        </div>

        {canAct && (link ? (
          <Button variant="outline" size="sm" onClick={() => onShowLink(invoice)}>
            <Link2 size={15} /> Link de pagamento
          </Button>
        ) : (
          <Button variant="outline" size="sm" onClick={() => onGenerateLink(invoice)} disabled={generating}>
            <Link2 size={15} /> {generating ? 'Gerando…' : 'Gerar link'}
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
              <CheckCircle2 /> Marcar como paga
            </DropdownMenuItem>
            {canAct && (link ? (
              <DropdownMenuItem onSelect={() => onShowLink(invoice)}><Link2 /> Ver link de pagamento</DropdownMenuItem>
            ) : (
              <DropdownMenuItem onSelect={() => onGenerateLink(invoice)}><Link2 /> Gerar link de pagamento</DropdownMenuItem>
            ))}
            {canAct && paymentLinksAvailable && (
              <DropdownMenuItem disabled={sending} onSelect={() => onSendPaymentLink(invoice)}>
                <Send /> {sending ? 'Enviando…' : 'Enviar link de pagamento'}
              </DropdownMenuItem>
            )}
            <DropdownMenuItem
              disabled={!canAct}
              onSelect={() => canAct && onCancel(invoice)}
              className="text-danger data-[highlighted]:text-danger"
            >
              <Ban /> Cancelar
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  )
}

export default function InvoicesIndex() {
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
      title: 'Marcar como paga?',
      description: 'Confirme o recebimento manual desta cobrança. O status muda para paga.',
      confirmLabel: 'Marcar como paga',
      icon: CheckCircle2,
      tone: '#10B981',
    })
    if (ok) markPaid.mutate(inv.id)
  }
  const onCancel = async (inv) => {
    const ok = await confirm({
      title: 'Cancelar cobrança?',
      description: 'A cobrança será cancelada e não poderá mais ser paga pelo cliente.',
      confirmLabel: 'Cancelar cobrança',
      cancelLabel: 'Voltar',
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
        eyebrow="Financeiro"
        title="Cobranças"
        icon={Receipt}
        color="#F97316"
        description="Cobranças da agência para seus clientes."
        actions={<Button onClick={() => setCreateOpen(true)}><Plus size={18} /> Nova cobrança</Button>}
      />

      <div className="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
        <StatCard label="Em aberto" value={brl(stats.open)} icon={CircleDollarSign} color="#0EA5E9" sub="aguardando pagamento" />
        <StatCard label="Total pago" value={brl(stats.paid)} icon={Wallet} color="#10B981" sub="cobranças quitadas" />
        <StatCard label="Vencidas" value={stats.overdueCount} icon={AlertTriangle} color="#F43F5E" sub={brl(stats.overdueSum)} />
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
          title={list.length === 0 ? 'Nenhuma cobrança' : 'Nada neste filtro'}
          description={list.length === 0 ? 'Registre a primeira cobrança para um cliente.' : 'Tente outro status.'}
          action={list.length === 0 ? <Button onClick={() => setCreateOpen(true)}><Plus size={18} /> Nova cobrança</Button> : null}
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
