import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { subtasksApi } from '@/api'
import { keys } from '@/api/queryKeys'
import { useWorkspaceMembers } from '@/hooks/useData'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { DatePicker } from '@/components/ui/date-picker'
import { Avatar } from '@/components/ui/avatar'
import { Spinner } from '@/components/ui/feedback'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu'
import { cn } from '@/lib/utils'
import { date } from '@/lib/formatters'
import { ListChecks, Plus, Check, Wand2, Pencil, UserPlus, X } from 'lucide-react'

// The right-rail checklist: progress bar, toggleable items, inline add, plus
// per-item edit (title + due date) and assignment.
export default function SubtasksPanel({ ticketId, subtasks = [], onAdd, adding = false, onGenerate, generating = false }) {
  const qc = useQueryClient()
  const { data: members } = useWorkspaceMembers()
  const people = members || []
  const [title, setTitle] = useState('')
  const [pending, setPending] = useState({}) // optimistic in-flight toggles
  const [editingId, setEditingId] = useState(null)
  const [draft, setDraft] = useState({ title: '', due_date: '' })
  const [saving, setSaving] = useState(false)

  const items = [...(subtasks || [])].sort((a, b) => (a.position ?? 0) - (b.position ?? 0))
  const total = items.length
  const done = items.filter((s) => s.done).length
  const pct = total ? Math.round((done / total) * 100) : 0

  const refresh = () => {
    qc.invalidateQueries({ queryKey: keys.ticket(ticketId) })
    qc.invalidateQueries({ queryKey: ['tasks'] })
  }

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
      refresh()
    }
  }

  // Assign (or clear) — patches assignee_id (a user id) and refreshes.
  const assign = async (sub, userId) => {
    await subtasksApi.update(sub.id, { assignee_id: userId })
    refresh()
  }

  const startEdit = (sub) => {
    setEditingId(sub.id)
    setDraft({ title: sub.title || '', due_date: sub.due_date || '' })
  }

  const cancelEdit = () => { setEditingId(null); setDraft({ title: '', due_date: '' }) }

  const saveEdit = async (sub) => {
    const value = draft.title.trim()
    if (!value || saving) return
    setSaving(true)
    try {
      await subtasksApi.update(sub.id, { title: value, due_date: draft.due_date || null })
      cancelEdit()
      refresh()
    } finally {
      setSaving(false)
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

            // ── Edit mode ──
            if (editingId === sub.id) {
              return (
                <div key={sub.id} className="space-y-2 bg-surface-muted/40 px-4 py-3">
                  <Input
                    autoFocus
                    value={draft.title}
                    onChange={(e) => setDraft((d) => ({ ...d, title: e.target.value }))}
                    onKeyDown={(e) => { if (e.key === 'Enter') saveEdit(sub); if (e.key === 'Escape') cancelEdit() }}
                    placeholder="Título da subtarefa"
                    className="h-9"
                  />
                  <div className="flex items-center gap-2">
                    <DatePicker
                      value={draft.due_date || ''}
                      onChange={(v) => setDraft((d) => ({ ...d, due_date: v }))}
                      placeholder="Prazo"
                      className="h-9 flex-1"
                    />
                    <button
                      type="button"
                      onClick={cancelEdit}
                      className="flex size-9 shrink-0 items-center justify-center rounded-xl border border-border text-ink-muted transition hover:bg-surface-muted"
                      aria-label="Cancelar"
                    >
                      <X size={16} />
                    </button>
                    <button
                      type="button"
                      onClick={() => saveEdit(sub)}
                      disabled={!draft.title.trim() || saving}
                      className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-brand-gradient text-white shadow-sm transition active:scale-95 disabled:opacity-40"
                      aria-label="Salvar"
                    >
                      {saving ? <Spinner size={14} className="border-white/30 border-t-white" /> : <Check size={16} strokeWidth={2.6} />}
                    </button>
                  </div>
                </div>
              )
            }

            // ── Display mode ──
            return (
              <div key={sub.id} className="group flex items-start gap-2.5 px-4 py-2.5">
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
                    {sub.due_date && (
                      <span className={cn(!isDone && sub.overdue && 'font-bold text-danger')}>
                        {!isDone && sub.overdue && '⚠ '}{date(sub.due_date)}
                      </span>
                    )}
                    {sub.estimate_hours != null && <span>· {sub.estimate_hours}h</span>}
                  </div>
                </div>

                {/* Assignee + edit — assignee avatar always shows when set. */}
                <div className="flex shrink-0 items-center gap-1">
                  <AssigneeControl sub={sub} people={people} onAssign={assign} />
                  <button
                    type="button"
                    onClick={() => startEdit(sub)}
                    className="flex size-7 items-center justify-center rounded-lg text-ink-muted opacity-0 transition hover:bg-surface-muted hover:text-ink group-hover:opacity-100"
                    aria-label="Editar subtarefa"
                    title="Editar"
                  >
                    <Pencil size={13} />
                  </button>
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

// Small assignee picker: shows the assignee's avatar, or — when unassigned — a
// permanently visible dashed-circle affordance (the row must read as
// assignable at a glance). Opens a member dropdown that patches assignee_id.
function AssigneeControl({ sub, people, onAssign }) {
  const currentId = sub.assignee_id
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          type="button"
          className={cn(
            'flex size-7 items-center justify-center rounded-full transition',
            sub.assignee_name
              ? 'opacity-100'
              : 'border border-dashed border-ink-faint/60 text-ink-faint hover:border-brand hover:bg-brand/5 hover:text-brand',
          )}
          aria-label={sub.assignee_name ? `Responsável: ${sub.assignee_name}` : 'Atribuir subtarefa'}
          title={sub.assignee_name || 'Atribuir responsável'}
        >
          {sub.assignee_name ? <Avatar name={sub.assignee_name} size={22} /> : <UserPlus size={13} />}
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="max-h-72 overflow-y-auto">
        <DropdownMenuLabel>Atribuir a</DropdownMenuLabel>
        <DropdownMenuItem onClick={() => onAssign(sub, null)}>
          <span className="text-ink-muted">Sem responsável</span>
          {!currentId && <Check size={14} className="ml-auto !text-brand" />}
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        {people.map((p) => {
          const userId = p.user_id ?? p.id
          return (
            <DropdownMenuItem key={p.id} onClick={() => onAssign(sub, userId)}>
              <Avatar name={p.name} src={p.avatar_url} size={20} />
              <span className="truncate">{p.name}</span>
              {currentId === userId && <Check size={14} className="ml-auto !text-brand" />}
            </DropdownMenuItem>
          )
        })}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
