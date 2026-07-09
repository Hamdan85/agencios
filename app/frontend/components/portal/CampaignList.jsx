import { FileBarChart, LayoutGrid, ChevronRight, CheckCircle2, Bell } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { date } from '@/lib/formatters'

const STATUS_STYLE = {
  active: { bg: '#ECFDF5', fg: '#059669', label: 'Em andamento' },
  paused: { bg: '#FEF3C7', fg: '#B45309', label: 'Pausada' },
  completed: { bg: '#EEF2FF', fg: '#4F46E5', label: 'Finalizada' },
  archived: { bg: '#F1F5F9', fg: '#64748B', label: 'Arquivada' },
}

function StatusPill({ status, label }) {
  const s = STATUS_STYLE[status] || STATUS_STYLE.archived
  return (
    <span className="rounded-full px-2.5 py-0.5 text-[11px] font-bold uppercase tracking-wide"
      style={{ background: s.bg, color: s.fg }}>
      {label || s.label}
    </span>
  )
}

// The central's landing: every campaign the client has, as a tappable card.
export default function CampaignList({ campaigns = [], onOpen, accent = '#7C3AED' }) {
  if (!campaigns.length) {
    return (
      <div className="rounded-2xl border border-dashed border-border bg-surface py-16 text-center">
        <LayoutGrid className="mx-auto mb-3 text-ink-muted" size={28} />
        <p className="font-semibold text-ink">Nenhuma campanha por aqui ainda</p>
        <p className="mt-1 text-sm text-ink-muted">Assim que sua agência iniciar uma campanha, ela aparece aqui.</p>
      </div>
    )
  }

  return (
    <div>
      <h1 className="mb-1 font-display text-2xl font-extrabold tracking-tight text-ink">Suas campanhas</h1>
      <p className="mb-5 text-sm text-ink-muted">Acompanhe o andamento, aprove conteúdos e veja os resultados.</p>

      <div className="grid gap-3 sm:grid-cols-2">
        {campaigns.map((c) => {
          const pending = c.counts?.pending_approval || 0
          return (
            <Card key={c.id} onClick={() => onOpen(c)}
              className="cursor-pointer p-5 transition hover:-translate-y-0.5 hover:shadow-lg">
              <div className="mb-3 flex items-start justify-between gap-2">
                <div className="flex items-center gap-2.5">
                  <span className="size-3 shrink-0 rounded-full" style={{ background: c.color || accent }} />
                  <h2 className="font-display text-lg font-bold text-ink">{c.name}</h2>
                </div>
                <StatusPill status={c.status} label={c.status_label} />
              </div>

              <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-ink-muted">
                <span className="inline-flex items-center gap-1.5"><LayoutGrid size={14} /> {c.counts?.tickets || 0} conteúdo(s)</span>
                {c.has_report && (
                  <span className="inline-flex items-center gap-1.5 font-semibold" style={{ color: accent }}>
                    <FileBarChart size={14} /> Relatório pronto
                  </span>
                )}
                {c.status === 'completed' && !c.has_report && (
                  <span className="inline-flex items-center gap-1.5"><CheckCircle2 size={14} /> Finalizada</span>
                )}
                {c.period?.completed_at && (
                  <span className="text-ink-faint">· concluída em {date(c.period.completed_at)}</span>
                )}
              </div>

              <div className="mt-4 flex items-center justify-between">
                {pending > 0 ? (
                  <span className="inline-flex items-center gap-1.5 rounded-full bg-amber/15 px-2.5 py-1 text-xs font-bold text-[#B45309]">
                    <Bell size={13} /> {pending} aguardando sua aprovação
                  </span>
                ) : <span />}
                <span className="inline-flex items-center gap-1 text-sm font-semibold" style={{ color: accent }}>
                  Abrir <ChevronRight size={16} />
                </span>
              </div>
            </Card>
          )
        })}
      </div>
    </div>
  )
}
