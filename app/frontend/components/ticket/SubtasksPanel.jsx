import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { subtasksApi } from '@/api'
import { keys } from '@/api/queryKeys'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/feedback'
import { cn } from '@/lib/utils'
import { date } from '@/lib/formatters'
import { ListChecks, Plus, Check, Wand2 } from 'lucide-react'

// The right-rail checklist: progress bar, toggleable items, inline add.
export default function SubtasksPanel({ ticketId, subtasks = [], onAdd, adding = false, onGenerate, generating = false }) {
  const qc = useQueryClient()
  const [title, setTitle] = useState('')
  const [pending, setPending] = useState({}) // optimistic in-flight toggles

  const items = [...(subtasks || [])].sort((a, b) => (a.position ?? 0) - (b.position ?? 0))
  const total = items.length
  const done = items.filter((s) => s.done).length
  const pct = total ? Math.round((done / total) * 100) : 0

  const toggle = async (sub) => {
    const next = !sub.done
    setPending((p) => ({ ...p, [sub.id]: next }))
    try {
      await subtasksApi.update(sub.id, { done: next })
    } finally {
      setPending((p) => {
        const { [sub.id]: _omit, ...rest } = p
        return rest
      })
      qc.invalidateQueries({ queryKey: keys.ticket(ticketId) })
      qc.invalidateQueries({ queryKey: ['tasks'] })
    }
  }

  const submit = (e) => {
    e.preventDefault()
    const value = title.trim()
    if (!value || adding) return
    onAdd?.({ title: value })
    setTitle('')
  }

  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border p-4">
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <div className="flex size-8 items-center justify-center rounded-xl" style={{ background: '#10B98118', color: '#10B981' }}>
              <ListChecks size={16} strokeWidth={2.3} />
            </div>
            <h3 className="font-display text-sm font-bold text-ink">Subtarefas</h3>
          </div>
          <div className="flex items-center gap-2">
            {onGenerate && (
              <button
                type="button"
                onClick={() => onGenerate()}
                disabled={generating}
                title="Gerar a checklist de produção com IA a partir do brief e do escopo"
                className="inline-flex items-center gap-1 rounded-lg px-2 py-1 text-xs font-bold text-emerald transition hover:bg-emerald/10 disabled:opacity-50"
              >
                {generating ? <Spinner size={12} className="border-emerald/30 border-t-emerald" /> : <Wand2 size={12} />}
                IA
              </button>
            )}
            <span className="font-mono text-xs font-bold text-ink-muted">{done}/{total}</span>
          </div>
        </div>
        {total > 0 && (
          <div className="mt-3 h-2 overflow-hidden rounded-full bg-surface-muted">
            <div
              className="h-full rounded-full bg-gradient-to-r from-emerald to-teal transition-all duration-500"
              style={{ width: `${pct}%` }}
            />
          </div>
        )}
      </div>

      <div className="divide-y divide-border">
        {items.length === 0 ? (
          <p className="px-4 py-6 text-center text-sm text-ink-muted">Nenhuma subtarefa ainda.</p>
        ) : (
          items.map((sub) => {
            const isDone = sub.id in pending ? pending[sub.id] : sub.done
            const inFlight = sub.id in pending
            return (
              <div key={sub.id} className="flex items-start gap-2.5 px-4 py-2.5">
                <button
                  type="button"
                  onClick={() => toggle(sub)}
                  disabled={inFlight}
                  className={cn(
                    'mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-md border-2 transition-all',
                    isDone ? 'border-emerald bg-emerald text-white' : 'border-border bg-surface hover:border-emerald',
                  )}
                >
                  {inFlight ? <Spinner size={11} className="border-emerald/30 border-t-emerald" /> : isDone && <Check size={13} strokeWidth={3} />}
                </button>
                <div className="min-w-0 flex-1">
                  <p className={cn('text-sm leading-snug', isDone ? 'text-ink-faint line-through' : 'text-ink')}>
                    {sub.title}
                  </p>
                  <div className="mt-0.5 flex flex-wrap items-center gap-x-2 text-[11px] text-ink-muted">
                    {sub.due_date && <span>{date(sub.due_date)}</span>}
                    {sub.assignee_name && <span>· {sub.assignee_name}</span>}
                  </div>
                </div>
              </div>
            )
          })
        )}
      </div>

      <form onSubmit={submit} className="flex items-center gap-2 border-t border-border p-3">
        <Input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Adicionar subtarefa…"
          className="h-9"
        />
        <button
          type="submit"
          disabled={!title.trim() || adding}
          className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-brand-gradient text-white shadow-sm transition active:scale-95 disabled:opacity-40"
        >
          {adding ? <Spinner size={14} className="border-white/30 border-t-white" /> : <Plus size={16} strokeWidth={2.6} />}
        </button>
      </form>
    </Card>
  )
}
