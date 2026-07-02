import { useEffect, useState } from 'react'
import { Sparkles, FolderOpen } from 'lucide-react'
import { PRIORITY_META } from '@/lib/constants'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { ProjectSelect } from '@/components/ui/entity-select'
import {
  Select, SelectTrigger, SelectValue, SelectContent, SelectItem,
} from '@/components/ui/select'

const EMPTY = {
  project_id: '',
  title: '',
  brief: '',
  priority: 'medium',
}

// The create-ticket dialog used by the board header. A ticket is born in the
// Ideação column, so creation captures ONLY the context (project, title, brief).
// Tipo de criativo, canais, prazo e agendamento são definidos depois, em cada
// etapa do funil (Escopo → Produção → Agendado) — ver FieldGroup.
//
// `defaultProjectId` pre-selects the project (e.g. when opened from a project
// view); the board passes none and the user picks one.
export function NewTicketDialog({ open, onOpenChange, create, defaultProjectId }) {
  const initial = () => ({ ...EMPTY, project_id: defaultProjectId || '' })
  const [form, setForm] = useState(initial)

  const set = (key, value) => setForm((f) => ({ ...f, [key]: value }))
  const reset = () => setForm(initial())

  // Each time the dialog opens within a project, default to that project.
  useEffect(() => {
    if (open && defaultProjectId) set('project_id', defaultProjectId)
  }, [open, defaultProjectId])

  const submit = (e) => {
    e.preventDefault()
    if (!form.title.trim() || !form.project_id) return
    const brief = form.brief.trim()
    const payload = {
      project_id: form.project_id,
      title: form.title.trim(),
      priority: form.priority,
      ...(brief ? { fields: { brief } } : {}),
    }
    create.mutate(payload, {
      onSuccess: () => {
        reset()
        onOpenChange(false)
      },
    })
  }

  const handleOpenChange = (next) => {
    if (!next) reset()
    onOpenChange(next)
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="max-w-xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <span className="flex size-9 items-center justify-center rounded-xl bg-brand-soft text-brand">
              <Sparkles size={18} strokeWidth={2.3} />
            </span>
            Novo ticket
          </DialogTitle>
          <DialogDescription>
            Comece pelo contexto. Tipo de criativo, canais e prazo são definidos depois, na etapa de Escopo.
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={submit} className="space-y-4">
          {/* project */}
          <div className="space-y-1.5">
            <Label htmlFor="nt-project">Campanha</Label>
            <ProjectSelect
              id="nt-project"
              variant="field"
              value={form.project_id}
              onChange={(v) => set('project_id', v || '')}
              placeholder="Selecione uma campanha"
              emptyMessage="Crie uma campanha primeiro para abrir tickets."
              listParams={{ exclude_archived: true }}
            />
          </div>

          {/* title */}
          <div className="space-y-1.5">
            <Label htmlFor="nt-title">Título</Label>
            <Input
              id="nt-title"
              autoFocus
              value={form.title}
              onChange={(e) => set('title', e.target.value)}
              placeholder="Ex.: Lançamento — coleção de inverno"
            />
          </div>

          {/* brief — the ideation context */}
          <div className="space-y-1.5">
            <Label htmlFor="nt-brief">Brief / contexto</Label>
            <Textarea
              id="nt-brief"
              rows={4}
              value={form.brief}
              onChange={(e) => set('brief', e.target.value)}
              placeholder="Descreva o contexto, a mensagem e o tom desejado… (opcional, você pode evoluir na Ideação)"
            />
          </div>

          {/* priority */}
          <div className="space-y-1.5">
            <Label htmlFor="nt-priority">Prioridade</Label>
            <Select value={form.priority} onValueChange={(v) => set('priority', v)}>
              <SelectTrigger id="nt-priority" className="max-w-[220px]">
                <SelectValue placeholder="Prioridade" />
              </SelectTrigger>
              <SelectContent>
                {Object.entries(PRIORITY_META).map(([key, m]) => (
                  <SelectItem key={key} value={key}>
                    <span className="inline-flex items-center gap-2">
                      <span className="size-2 rounded-full" style={{ background: m.dot }} />
                      {m.label}
                    </span>
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <DialogFooter className="pt-2">
            <Button type="button" variant="ghost" onClick={() => handleOpenChange(false)}>Cancelar</Button>
            <Button type="submit" disabled={create.isPending || !form.title.trim() || !form.project_id}>
              {create.isPending ? 'Criando…' : (<><FolderOpen size={16} /> Criar ticket</>)}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

export default NewTicketDialog
