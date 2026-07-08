import { useEffect, useState } from 'react'
import { ShieldCheck, Rocket, CalendarClock } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Switch } from '@/components/ui/switch'

const WEEKDAYS = [
  { v: 1, label: 'Seg' }, { v: 2, label: 'Ter' }, { v: 3, label: 'Qua' },
  { v: 4, label: 'Qui' }, { v: 5, label: 'Sex' }, { v: 6, label: 'Sáb' }, { v: 0, label: 'Dom' },
]

// Mirror of Tickets::ProjectSettings#defaults — the client-side defaults for a
// project's approval/publish/posting-window config.
export const DEFAULT_PROJECT_SETTINGS = {
  require_client_approval: true,
  auto_publish_after_approval: false,
  posting_window: {
    weekdays: [1, 2, 3, 4, 5],
    times: ['09:00', '12:00', '18:00'],
    min_gap_minutes: 120,
    timezone: 'America/Sao_Paulo',
  },
}

// Coerce a (possibly partial / server-resolved) settings object into the full
// shape the editor expects, so `value` always has a posting_window.
export function normalizeProjectSettings(raw) {
  const s = raw || {}
  const w = s.posting_window || {}
  return {
    require_client_approval: s.require_client_approval ?? true,
    auto_publish_after_approval: !!s.auto_publish_after_approval,
    posting_window: {
      weekdays: w.weekdays || [...DEFAULT_PROJECT_SETTINGS.posting_window.weekdays],
      times: w.times || [...DEFAULT_PROJECT_SETTINGS.posting_window.times],
      min_gap_minutes: w.min_gap_minutes ?? 120,
      timezone: w.timezone || 'America/Sao_Paulo',
    },
  }
}

// Controlled editor for a project's approval/publish/posting-window config.
// `value` is a normalized settings object; `onChange(next)` receives the full
// updated object. `resetKey` reseeds the free-text "times" buffer (e.g. on
// dialog open or when switching to another project).
export function ProjectSettingsFields({ value, onChange, resetKey }) {
  const s = value
  const w = s.posting_window
  const [timesText, setTimesText] = useState(w.times.join(', '))

  // Reseed the local text buffer only when the source record changes — not on
  // every keystroke (which would strip a trailing comma mid-typing).
  useEffect(() => {
    setTimesText((value.posting_window.times || []).join(', '))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resetKey])

  const patchWindow = (p) => onChange({ ...s, posting_window: { ...w, ...p } })
  const toggleDay = (v) => patchWindow({
    weekdays: w.weekdays.includes(v) ? w.weekdays.filter((x) => x !== v) : [...w.weekdays, v],
  })
  const onTimes = (text) => {
    setTimesText(text)
    patchWindow({ times: text.split(',').map((t) => t.trim()).filter(Boolean) })
  }

  return (
    <div className="flex flex-col gap-4">
      <Card className="p-5">
        <div className="flex items-start gap-3">
          <ShieldCheck className="mt-0.5 text-brand" size={20} />
          <div className="flex-1">
            <p className="font-semibold text-ink">Exigir aprovação do cliente</p>
            <p className="text-sm text-ink-muted">O GO para em Produção e o cliente recebe o link de aprovação por e-mail.</p>
          </div>
          <Switch checked={s.require_client_approval} onCheckedChange={(v) => onChange({ ...s, require_client_approval: v })} />
        </div>
      </Card>

      <Card className="p-5">
        <div className="flex items-start gap-3">
          <Rocket className="mt-0.5 text-brand" size={20} />
          <div className="flex-1">
            <p className="font-semibold text-ink">Publicar após aprovação</p>
            <p className="text-sm text-ink-muted">Quando todos os criativos forem aprovados, o post é agendado automaticamente.</p>
          </div>
          <Switch checked={s.auto_publish_after_approval} onCheckedChange={(v) => onChange({ ...s, auto_publish_after_approval: v })} />
        </div>
      </Card>

      <Card className="p-5">
        <div className="mb-3 flex items-center gap-2">
          <CalendarClock className="text-brand" size={20} />
          <p className="font-semibold text-ink">Janela de postagem</p>
        </div>
        <div className="mb-3 flex flex-wrap gap-1.5">
          {WEEKDAYS.map((d) => (
            <button key={d.v} type="button" onClick={() => toggleDay(d.v)}
              className={`rounded-lg px-3 py-1.5 text-sm font-medium transition ${w.weekdays.includes(d.v) ? 'bg-brand text-white' : 'bg-surface-muted text-ink-muted'}`}>
              {d.label}
            </button>
          ))}
        </div>
        <label className="mb-1 block text-xs font-medium text-ink-muted">Horários (separados por vírgula)</label>
        <input value={timesText} onChange={(e) => onTimes(e.target.value)} placeholder="09:00, 12:00, 18:00"
          className="mb-3 w-full rounded-xl border border-border bg-surface px-3.5 py-2.5 text-sm" />
        <label className="mb-1 block text-xs font-medium text-ink-muted">Intervalo mínimo entre posts (min)</label>
        <input type="number" value={w.min_gap_minutes} onChange={(e) => patchWindow({ min_gap_minutes: Number(e.target.value) || 0 })}
          className="w-full rounded-xl border border-border bg-surface px-3.5 py-2.5 text-sm" />
      </Card>
    </div>
  )
}

export default ProjectSettingsFields
