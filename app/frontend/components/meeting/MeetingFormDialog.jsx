import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Plus, CalendarPlus, X } from 'lucide-react'
import { useWorkspaceMembers } from '@/hooks/useData'
import { Button } from '@/components/ui/button'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Avatar } from '@/components/ui/avatar'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose,
} from '@/components/ui/dialog'
import { ClientSelect } from '@/components/ui/entity-select'
import { DateTimePicker } from '@/components/ui/date-picker'

const EMPTY_FORM = { title: '', starts_at: '', ends_at: '', client_id: '', client_name: '', notes: '', attendees: [] }

// Attendee picker: workspace members join with one click (their e-mail resolves
// on the backend), external guests are added by e-mail. Everyone listed gets
// the Calendar invite and sees the meeting in their own /reunioes.
export function AttendeesField({ value = [], onChange }) {
  const { t } = useTranslation('meetings')
  const { data: members } = useWorkspaceMembers()
  const [email, setEmail] = useState('')

  const has = (entry) => value.some((a) =>
    (entry.user_id && a.user_id === entry.user_id) || (entry.email && a.email === entry.email))
  const add = (entry) => { if (!has(entry)) onChange([...value, entry]) }
  const remove = (idx) => onChange(value.filter((_, i) => i !== idx))
  const addEmail = () => {
    const v = email.trim().toLowerCase()
    if (!v || !v.includes('@')) return
    add({ email: v })
    setEmail('')
  }

  const available = (members || []).filter((m) => !has({ user_id: m.user_id }))

  return (
    <div className="space-y-2">
      {value.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {value.map((a, i) => (
            <span key={a.user_id || a.email} className="inline-flex items-center gap-1.5 rounded-full bg-surface-muted py-1 pl-2.5 pr-1.5 text-xs font-semibold text-ink-secondary">
              {a.name || a.email}
              <button type="button" aria-label={t('form.removeAttendee')} onClick={() => remove(i)} className="grid size-4 place-items-center rounded-full text-ink-faint hover:bg-surface hover:text-ink">
                <X size={11} strokeWidth={2.5} />
              </button>
            </span>
          ))}
        </div>
      )}
      {available.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {available.map((m) => (
            <button
              key={m.user_id}
              type="button"
              onClick={() => add({ user_id: m.user_id, name: m.name, email: m.email })}
              className="inline-flex items-center gap-1.5 rounded-full border border-dashed border-border py-1 pl-1.5 pr-2.5 text-xs font-semibold text-ink-muted transition hover:border-teal/50 hover:text-ink"
            >
              <Avatar name={m.name} src={m.avatar_url} size={18} />
              {m.name}
              <Plus size={11} strokeWidth={2.5} />
            </button>
          ))}
        </div>
      )}
      <div className="flex gap-2">
        <Input
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addEmail() } }}
          placeholder={t('form.guestEmailPlaceholder')}
          type="email"
          className="min-w-0 flex-1"
        />
        <Button type="button" variant="outline" onClick={addEmail} disabled={!email.trim()}>
          <Plus size={15} /> {t('form.add')}
        </Button>
      </div>
    </div>
  )
}

// Create/edit dialog shared by /reunioes and the client page. `defaultClient`
// prefills the client picker when scheduling from a client's own page.
export function MeetingFormDialog({ open, onOpenChange, editing, createMutation, updateMutation, defaultClient }) {
  const { t } = useTranslation('meetings')
  const isEdit = !!editing
  const mutation = isEdit ? updateMutation : createMutation
  const [form, setForm] = useState(EMPTY_FORM)
  const set = (k) => (v) => setForm((f) => ({ ...f, [k]: v }))

  const key = `${open}:${editing?.id ?? 'new'}`
  const [syncedKey, setSyncedKey] = useState(null)
  if (open && key !== syncedKey) {
    setSyncedKey(key)
    setForm(isEdit
      ? {
          title: editing.title || '',
          starts_at: editing.starts_at ? editing.starts_at.slice(0, 16) : '',
          ends_at: editing.ends_at ? editing.ends_at.slice(0, 16) : '',
          client_id: editing.client_id ? String(editing.client_id) : '',
          client_name: editing.client_name || '',
          notes: editing.notes || '',
          attendees: Array.isArray(editing.attendees) ? editing.attendees : [],
        }
      : {
          ...EMPTY_FORM,
          client_id: defaultClient?.id ? String(defaultClient.id) : '',
          client_name: defaultClient?.name || '',
        })
  }

  const submit = (e) => {
    e.preventDefault()
    if (!form.title.trim() || !form.starts_at) return
    const payload = {
      title: form.title.trim(),
      starts_at: new Date(form.starts_at).toISOString(),
      ends_at: form.ends_at ? new Date(form.ends_at).toISOString() : null,
      client_id: form.client_id || null,
      notes: form.notes,
      attendees: form.attendees,
    }
    const onSuccess = () => { setSyncedKey(null); onOpenChange(false) }
    if (isEdit) mutation.mutate({ id: editing.id, data: payload }, { onSuccess })
    else mutation.mutate(payload, { onSuccess })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <div className="mb-1 flex size-11 items-center justify-center rounded-2xl" style={{ background: '#14B8A616', color: '#14B8A6' }}>
            <CalendarPlus size={22} strokeWidth={2.2} />
          </div>
          <DialogTitle>{isEdit ? t('form.editTitle') : t('form.createTitle')}</DialogTitle>
          <DialogDescription>{t('form.description')}</DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-3.5">
          <div className="space-y-1.5">
            <Label htmlFor="mt-title">{t('form.titleLabel')}</Label>
            <Input id="mt-title" autoFocus required value={form.title} onChange={(e) => set('title')(e.target.value)} placeholder={t('form.titlePlaceholder')} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="mt-start">{t('form.startLabel')}</Label>
              <DateTimePicker id="mt-start" value={form.starts_at} onChange={set('starts_at')} placeholder={t('form.startPlaceholder')} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="mt-end">{t('form.endLabel')}</Label>
              <DateTimePicker id="mt-end" value={form.ends_at} onChange={set('ends_at')} placeholder={t('form.endPlaceholder')} />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>{t('form.clientLabel')}</Label>
            <ClientSelect
              variant="field"
              clearable
              value={form.client_id}
              onChange={(v, opt) => setForm((f) => ({ ...f, client_id: v || '', client_name: opt?.label || '' }))}
              placeholder={t('form.clientPlaceholder')}
              initialOption={form.client_id ? { value: form.client_id, label: form.client_name } : null}
            />
          </div>
          <div className="space-y-1.5">
            <Label>{t('form.attendeesLabel')}</Label>
            <AttendeesField value={form.attendees} onChange={set('attendees')} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="mt-notes">{t('form.notesLabel')}</Label>
            <Textarea id="mt-notes" value={form.notes} onChange={(e) => set('notes')(e.target.value)} placeholder={t('form.notesPlaceholder')} />
          </div>
          <DialogFooter>
            <DialogClose asChild><Button type="button" variant="ghost">{t('form.cancel')}</Button></DialogClose>
            <Button type="submit" disabled={mutation.isPending}>
              {mutation.isPending ? t('form.saving') : isEdit ? t('form.save') : t('form.schedule')}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

export default MeetingFormDialog
