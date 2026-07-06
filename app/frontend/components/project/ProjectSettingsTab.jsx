import { useEffect, useState } from 'react'
import { ShieldCheck, Rocket, CalendarClock } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Switch } from '@/components/ui/switch'
import { Button } from '@/components/ui/button'
import { useProjectMutations } from '@/hooks/useData'

const WEEKDAYS = [
  { v: 1, label: 'Seg' }, { v: 2, label: 'Ter' }, { v: 3, label: 'Qua' },
  { v: 4, label: 'Qui' }, { v: 5, label: 'Sex' }, { v: 6, label: 'Sáb' }, { v: 0, label: 'Dom' },
]

export default function ProjectSettingsTab({ project }) {
  const s = project.settings || {}
  const w = s.posting_window || {}
  const [requireApproval, setRequireApproval] = useState(!!s.require_client_approval)
  const [autoPublish, setAutoPublish] = useState(!!s.auto_publish_after_approval)
  const [weekdays, setWeekdays] = useState(w.weekdays || [1, 2, 3, 4, 5])
  const [times, setTimes] = useState((w.times || ['09:00', '12:00', '18:00']).join(', '))
  const [minGap, setMinGap] = useState(w.min_gap_minutes ?? 120)
  const { updateSettings } = useProjectMutations()

  useEffect(() => {
    setRequireApproval(!!s.require_client_approval)
    setAutoPublish(!!s.auto_publish_after_approval)
  }, [project.id]) // eslint-disable-line react-hooks/exhaustive-deps

  const toggleDay = (v) => setWeekdays((d) => (d.includes(v) ? d.filter((x) => x !== v) : [...d, v]))

  const save = () => updateSettings.mutate({
    id: project.id,
    settings: {
      require_client_approval: requireApproval,
      auto_publish_after_approval: autoPublish,
      posting_window: {
        weekdays,
        times: times.split(',').map((t) => t.trim()).filter(Boolean),
        min_gap_minutes: Number(minGap) || 0,
        timezone: w.timezone || 'America/Sao_Paulo',
      },
    },
  })

  return (
    <div className="flex flex-col gap-4">
      <Card className="p-5">
        <div className="flex items-start gap-3">
          <ShieldCheck className="mt-0.5 text-brand" size={20} />
          <div className="flex-1">
            <p className="font-semibold text-ink">Exigir aprovação do cliente</p>
            <p className="text-sm text-ink-muted">O GO para em Produção e o cliente recebe o link de aprovação por e-mail.</p>
          </div>
          <Switch checked={requireApproval} onCheckedChange={setRequireApproval} />
        </div>
      </Card>

      <Card className="p-5">
        <div className="flex items-start gap-3">
          <Rocket className="mt-0.5 text-brand" size={20} />
          <div className="flex-1">
            <p className="font-semibold text-ink">Publicar após aprovação</p>
            <p className="text-sm text-ink-muted">Quando todos os criativos forem aprovados, o post é agendado automaticamente.</p>
          </div>
          <Switch checked={autoPublish} onCheckedChange={setAutoPublish} />
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
              className={`rounded-lg px-3 py-1.5 text-sm font-medium transition ${weekdays.includes(d.v) ? 'bg-brand text-white' : 'bg-surface-muted text-ink-muted'}`}>
              {d.label}
            </button>
          ))}
        </div>
        <label className="mb-1 block text-xs font-medium text-ink-muted">Horários (separados por vírgula)</label>
        <input value={times} onChange={(e) => setTimes(e.target.value)} placeholder="09:00, 12:00, 18:00"
          className="mb-3 w-full rounded-xl border border-border bg-surface px-3.5 py-2.5 text-sm" />
        <label className="mb-1 block text-xs font-medium text-ink-muted">Intervalo mínimo entre posts (min)</label>
        <input type="number" value={minGap} onChange={(e) => setMinGap(e.target.value)}
          className="w-full rounded-xl border border-border bg-surface px-3.5 py-2.5 text-sm" />
      </Card>

      <div className="flex justify-end">
        <Button onClick={save} disabled={updateSettings.isPending}>
          {updateSettings.isPending ? 'Salvando…' : 'Salvar configurações'}
        </Button>
      </div>
    </div>
  )
}
