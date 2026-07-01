import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Receipt, Check, Link2, CheckCircle2, Send } from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { ClientSelect } from '@/components/ui/entity-select'
import { DatePicker } from '@/components/ui/date-picker'
import { useSettings, useInvoiceMutations } from '@/hooks/useData'
import { projectsApi } from '@/api'
import { maskCurrency, centsFromMasked, brl } from '@/lib/formatters'
import { cn } from '@/lib/utils'

const EMPTY_FORM = { client_id: '', amount: '', description: '', due_date: '', project_ids: [], send_payment_link: false }

// Create a client invoice. Pass `initialClientId` + `initialProjectIds` to
// prefill it from a project's context (e.g. "Iniciar cobrança" on a finalized
// project) — the client stays editable, the project just comes pre-checked.
// On success, swaps to a confirmation step with an explicit "Enviar ao
// cliente" action instead of just closing — the same for both entry points
// since this component is shared.
export function InvoiceFormDialog({ open, onOpenChange, initialClientId = '', initialProjectIds = [] }) {
  const [form, setForm] = useState(EMPTY_FORM)
  const [created, setCreated] = useState(null)
  const set = (k) => (v) => setForm((f) => ({ ...f, [k]: v }))
  const { data: settings } = useSettings()
  const paymentLinksAvailable = !!settings?.setting?.payment_links_available
  const { create, sendPaymentLink } = useInvoiceMutations()

  // Default "send payment link" ON whenever a payment link can actually be
  // generated (workspace-connected or the platform token) — a billing email
  // with no way to pay is the whole point missed. Still a switch, so a
  // manager can opt out for a specific invoice (e.g. already settled another
  // way).
  useEffect(() => {
    if (open) {
      setCreated(null)
      setForm({
        ...EMPTY_FORM,
        client_id: initialClientId || '',
        project_ids: initialProjectIds,
        send_payment_link: paymentLinksAvailable,
      })
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

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
      send_payment_link: paymentLinksAvailable && form.send_payment_link,
    }
    create.mutate(payload, { onSuccess: (d) => setCreated(d?.invoice) })
  }

  // ── Success step ────────────────────────────────────────────────
  if (created) {
    const alreadySent = paymentLinksAvailable && form.send_payment_link
    return (
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent>
          <DialogHeader>
            <div className="mb-1 flex size-11 items-center justify-center rounded-2xl bg-emerald/12 text-emerald">
              <CheckCircle2 size={22} strokeWidth={2.2} />
            </div>
            <DialogTitle>Cobrança criada!</DialogTitle>
            <DialogDescription>
              {created.client_name ? `${created.client_name} · ` : ''}{brl(created.amount_cents)}
            </DialogDescription>
          </DialogHeader>
          {paymentLinksAvailable && (
            <Button className="w-full" onClick={() => sendPaymentLink.mutate(created.id)} disabled={sendPaymentLink.isPending}>
              <Send size={16} />
              {sendPaymentLink.isPending ? 'Enviando…' : alreadySent ? 'Reenviar ao cliente' : 'Enviar ao cliente'}
            </Button>
          )}
          <DialogFooter>
            <Button variant="ghost" onClick={() => onOpenChange(false)}>Fechar</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    )
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
            <ClientSelect
              variant="field"
              value={form.client_id}
              onChange={(v) => setForm((f) => ({ ...f, client_id: v || '', project_ids: [] }))}
              placeholder="Selecione o cliente"
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
          {paymentLinksAvailable && (
            <div className="flex items-center justify-between gap-3 rounded-xl border border-border bg-surface-muted/50 p-3.5">
              <div className="flex items-center gap-2.5">
                <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-sky/12 text-sky">
                  <Link2 size={15} />
                </span>
                <div>
                  <p className="text-sm font-semibold text-ink">Gerar com link de pagamento</p>
                  <p className="text-xs text-ink-muted">Gera o link no Mercado Pago e envia por e-mail ao cliente.</p>
                </div>
              </div>
              <Switch checked={form.send_payment_link} onCheckedChange={set('send_payment_link')} />
            </div>
          )}
          <DialogFooter>
            <DialogClose asChild><Button type="button" variant="ghost">Cancelar</Button></DialogClose>
            <Button type="submit" disabled={create.isPending}>
              {create.isPending ? 'Registrando…' : 'Registrar cobrança'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

export default InvoiceFormDialog
