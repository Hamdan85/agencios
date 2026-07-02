import { useEffect, useState } from 'react'
import { Sparkles, Check } from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { ClientSelect } from '@/components/ui/entity-select'
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from '@/components/ui/select'
import { DatePicker } from '@/components/ui/date-picker'
import { useProjectMutations } from '@/hooks/useData'
import { maskCurrency, centsFromMasked, brl } from '@/lib/formatters'
import { cn } from '@/lib/utils'

const PALETTE = ['#7C3AED', '#EC4899', '#0EA5E9', '#10B981', '#F59E0B', '#6366F1', '#F43F5E', '#14B8A6']
const STATUS_OPTIONS = [
  { value: 'draft', label: 'Rascunho' },
  { value: 'active', label: 'Ativa' },
  { value: 'paused', label: 'Pausada' },
  { value: 'archived', label: 'Arquivada' },
  { value: 'completed', label: 'Finalizada' },
]
const EMPTY = { client_id: '', name: '', description: '', color: PALETTE[0], status: 'draft', starts_on: '', ends_on: '', budget: '' }

const fromProject = (p) => ({
  client_id: p.client_id || '',
  name: p.name || '',
  description: p.description || '',
  color: p.color || PALETTE[0],
  status: p.status || 'draft',
  starts_on: p.starts_on || '',
  ends_on: p.ends_on || '',
  budget: p.budget_cents != null ? brl(p.budget_cents).replace(/[^\d,]/g, '') : '',
})

// Create OR edit a project. Pass `project` to edit (prefilled), omit to create.
// Self-contained: owns the create/update mutations. `onSaved(project)` fires on
// success (e.g. to navigate to the new project or into its strategy planner).
export function ProjectFormDialog({ open, onOpenChange, project = null, onSaved }) {
  const editing = !!project
  const { create, update } = useProjectMutations()
  const mutation = editing ? update : create
  const [form, setForm] = useState(EMPTY)
  const set = (k) => (v) => setForm((f) => ({ ...f, [k]: v }))

  // Reset/prefill whenever the dialog opens.
  useEffect(() => {
    if (open) setForm(editing ? fromProject(project) : EMPTY)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  const submit = (e) => {
    e.preventDefault()
    if (!form.name.trim() || !form.client_id) return
    const payload = {
      client_id: form.client_id,
      name: form.name.trim(),
      description: form.description,
      color: form.color,
      status: form.status,
      starts_on: form.starts_on || null,
      ends_on: form.ends_on || null,
      budget_cents: form.budget ? centsFromMasked(form.budget) : null,
    }
    const opts = { onSuccess: (d) => { onOpenChange(false); onSaved?.(d?.project) } }
    if (editing) update.mutate({ id: project.id, data: payload }, opts)
    else create.mutate(payload, opts)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <div className="mb-1 flex size-11 items-center justify-center rounded-2xl" style={{ background: '#10B98116', color: '#10B981' }}>
            <Sparkles size={22} strokeWidth={2.2} />
          </div>
          <DialogTitle>{editing ? 'Editar campanha' : 'Nova campanha'}</DialogTitle>
          <DialogDescription>Agrupe tickets sob uma campanha de um cliente.</DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-3.5">
          <div className="space-y-1.5">
            <Label>Cliente</Label>
            <ClientSelect variant="field" value={form.client_id} onChange={(v) => set('client_id')(v || '')} placeholder="Selecione o cliente" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pj-name">Nome</Label>
            <Input id="pj-name" required value={form.name} onChange={(e) => set('name')(e.target.value)} placeholder="Ex: Campanha de verão" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pj-desc">Descrição</Label>
            <Textarea id="pj-desc" value={form.description} onChange={(e) => set('description')(e.target.value)} placeholder="Objetivo e escopo da campanha…" />
          </div>
          <div className="space-y-2">
            <Label>Cor</Label>
            <div className="flex flex-wrap gap-2">
              {PALETTE.map((c) => (
                <button
                  key={c}
                  type="button"
                  onClick={() => set('color')(c)}
                  className={cn('flex size-9 items-center justify-center rounded-xl transition-transform hover:scale-110', form.color === c && 'ring-2 ring-offset-2 ring-offset-surface')}
                  style={{ background: c, '--tw-ring-color': c }}
                  aria-label={`Cor ${c}`}
                >
                  {form.color === c && <Check size={16} className="text-white" strokeWidth={3} />}
                </button>
              ))}
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Status</Label>
              <Select value={form.status} onValueChange={set('status')}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {STATUS_OPTIONS.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="pj-budget">Orçamento (R$)</Label>
              <Input id="pj-budget" inputMode="decimal" value={form.budget} onChange={(e) => set('budget')(maskCurrency(e.target.value))} placeholder="0,00" />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="pj-start">Início</Label>
              <DatePicker id="pj-start" value={form.starts_on} onChange={set('starts_on')} placeholder="Data de início" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="pj-end">Fim</Label>
              <DatePicker id="pj-end" value={form.ends_on} onChange={set('ends_on')} placeholder="Data de fim" />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild><Button type="button" variant="ghost">Cancelar</Button></DialogClose>
            <Button type="submit" disabled={mutation.isPending || !form.client_id}>
              {mutation.isPending ? 'Salvando…' : editing ? 'Salvar' : 'Criar campanha'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

export default ProjectFormDialog
