import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Receipt, Plus, MoreHorizontal, Ban, Copy, Check, Wallet, Link2, CheckCircle2,
  CircleDollarSign, AlertTriangle, FileText, ExternalLink, Hash, Building2,
} from 'lucide-react'
import { useInvoices, useInvoiceMutations } from '@/hooks/useData'
import { clientsApi, projectsApi } from '@/api'
import { PageHeader, StatCard } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose,
} from '@/components/ui/dialog'
import { AsyncCombobox } from '@/components/ui/async-combobox'
import { DatePicker } from '@/components/ui/date-picker'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem,
} from '@/components/ui/dropdown-menu'
import {
  Tabs, TabsList, TabsTrigger,
} from '@/components/ui/tabs'
import { brl, date, relativeDay, maskCurrency, centsFromMasked } from '@/lib/formatters'
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

// ── Create dialog ──────────────────────────────────────────────
const EMPTY_FORM = { client_id: '', amount: '', description: '', due_date: '', project_ids: [] }

function InvoiceFormDialog({ open, onOpenChange, mutation }) {
  const [form, setForm] = useState(EMPTY_FORM)
  const set = (k) => (v) => setForm((f) => ({ ...f, [k]: v }))

  // Projects are scoped to the selected client (fetched on demand) rather than
  // loading every project across the workspace and filtering client-side.
  const projectsQuery = useQuery({
    queryKey: ['projects', 'invoice-picker', form.client_id],
    queryFn: () => projectsApi.list({ client_id: form.client_id, per: 100 }),
    enabled: !!form.client_id,
    select: (d) => d.projects,
  })
  const clientProjects = projectsQuery.data || []

  const toggleProject = (id) => setForm((f) => {
    const has = f.project_ids.includes(id)
    return { ...f, project_ids: has ? f.project_ids.filter((x) => x !== id) : [...f.project_ids, id] }
  })

  const submit = (e) => {
    e.preventDefault()
    if (!form.client_id || centsFromMasked(form.amount) <= 0) return
    const payload = {
      client_id: form.client_id,
      amount_cents: centsFromMasked(form.amount),
      description: form.description,
      due_date: form.due_date || null,
      project_ids: form.project_ids,
    }
    mutation.mutate(payload, { onSuccess: () => { setForm(EMPTY_FORM); onOpenChange(false) } })
  }

  return (
    <Dialog open={open} onOpenChange={(v) => { onOpenChange(v); if (!v) setForm(EMPTY_FORM) }}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <div className="mb-1 flex size-11 items-center justify-center rounded-2xl" style={{ background: '#F9731616', color: '#F97316' }}>
            <Receipt size={22} strokeWidth={2.2} />
          </div>
          <DialogTitle>Nova cobrança</DialogTitle>
          <DialogDescription>Registre uma cobrança para um cliente. Depois você pode gerar um link de pagamento ou marcá-la como paga.</DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-3.5">
          <div className="space-y-1.5">
            <Label>Cliente</Label>
            <AsyncCombobox
              variant="field"
              value={form.client_id}
              onChange={(v) => setForm((f) => ({ ...f, client_id: v || '', project_ids: [] }))}
              placeholder="Selecione o cliente"
              icon={Building2}
              queryKey={['clients', 'picker']}
              fetchPage={({ q, page }) => clientsApi.list({ q, page, per: 20 })}
              mapResponse={(d) => ({ items: d.clients || [], hasMore: d.meta?.has_more })}
              getOption={(c) => ({ value: c.id, label: c.name, description: c.company })}
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="iv-amount">Valor</Label>
              <div className="relative">
                <span className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-sm font-medium text-ink-muted">R$</span>
                <Input
                  id="iv-amount"
                  inputMode="decimal"
                  required
                  value={form.amount}
                  onChange={(e) => set('amount')(maskCurrency(e.target.value))}
                  placeholder="0,00"
                  className="pl-9"
                />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="iv-due">Vencimento</Label>
              <DatePicker id="iv-due" value={form.due_date} onChange={set('due_date')} placeholder="Selecione o vencimento" />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="iv-desc">Descrição</Label>
            <Textarea id="iv-desc" value={form.description} onChange={(e) => set('description')(e.target.value)} placeholder="Serviços prestados…" />
          </div>
          {form.client_id && clientProjects.length > 0 && (
            <div className="space-y-1.5">
              <Label>Projetos (opcional)</Label>
              <div className="flex flex-wrap gap-2">
                {clientProjects.map((p) => {
                  const active = form.project_ids.includes(p.id)
                  return (
                    <button
                      key={p.id}
                      type="button"
                      onClick={() => toggleProject(p.id)}
                      className={cn(
                        'inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-bold transition-colors',
                        active ? 'border-transparent text-white' : 'border-border bg-surface-muted text-ink-secondary hover:border-brand/40',
                      )}
                      style={active ? { background: p.color || '#7C3AED' } : undefined}
                    >
                      {active && <Check size={13} />} {p.name}
                    </button>
                  )
                })}
              </div>
            </div>
          )}
          <DialogFooter>
            <DialogClose asChild><Button type="button" variant="ghost">Cancelar</Button></DialogClose>
            <Button type="submit" disabled={mutation.isPending}>
              {mutation.isPending ? 'Registrando…' : 'Registrar cobrança'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

// ── Payment link dialog ────────────────────────────────────────
function PaymentLinkDialog({ invoice, open, onOpenChange }) {
  const [copied, setCopied] = useState(false)
  const charge = invoice?.charge
  const link = charge?.payment_link

  const copy = async () => {
    if (!link) return
    try {
      await navigator.clipboard.writeText(link)
      setCopied(true)
      setTimeout(() => setCopied(false), 1800)
    } catch { /* clipboard unavailable */ }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <div className="mb-1 flex size-11 items-center justify-center rounded-2xl" style={{ background: '#0EA5E916', color: '#0EA5E9' }}>
            <Link2 size={22} strokeWidth={2.2} />
          </div>
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

              <Button onClick={copy} variant={copied ? 'solid' : 'outline'} className="w-full">
                {copied ? <><Check size={16} /> Copiado!</> : <><Copy size={16} /> Copiar link</>}
              </Button>

              <a href={link} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1.5 text-sm font-semibold text-brand hover:underline">
                Abrir página de pagamento <ExternalLink size={14} />
              </a>

              <p className="text-center text-xs text-ink-muted">Envie este link ao cliente — a baixa é automática após o pagamento.</p>
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
function InvoiceRow({ invoice, onMarkPaid, onCancel, onGenerateLink, onShowLink, generating }) {
  const m = statusMeta(invoice.status)
  const rel = relativeDay(invoice.due_date)
  const canAct = !['paid', 'canceled'].includes(invoice.status)
  const link = invoice.charge?.payment_link

  return (
    <div className="flex flex-wrap items-center justify-between gap-4 p-4 transition-colors hover:bg-surface-muted/40">
      <div className="flex min-w-0 items-center gap-3">
        <div className="flex size-11 shrink-0 items-center justify-center rounded-xl" style={{ background: `${m.dot}18`, color: m.dot }}>
          <Receipt size={20} strokeWidth={2.2} />
        </div>
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
  const { create, cancel, markPaid, paymentLink } = useInvoiceMutations()
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

  const onMarkPaid = (inv) => { if (window.confirm('Marcar esta cobrança como paga?')) markPaid.mutate(inv.id) }
  const onCancel = (inv) => { if (window.confirm('Cancelar esta cobrança?')) cancel.mutate(inv.id) }
  const onGenerateLink = (inv) => paymentLink.mutate(inv.id, { onSuccess: () => setLinkInvoiceId(inv.id) })
  const onShowLink = (inv) => setLinkInvoiceId(inv.id)

  if (isLoading) return <PageLoader />

  return (
    <div>
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
              generating={generatingId === inv.id}
            />
          ))}
        </Card>
      )}

      <InvoiceFormDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
        mutation={create}
      />
      <PaymentLinkDialog
        invoice={linkInvoice}
        open={linkInvoiceId != null}
        onOpenChange={(v) => { if (!v) setLinkInvoiceId(null) }}
      />
    </div>
  )
}
