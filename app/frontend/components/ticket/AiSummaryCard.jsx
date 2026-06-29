import { statusMeta } from '@/lib/constants'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/feedback'
import { Sparkles, RefreshCw, Wand2 } from 'lucide-react'
import { cn } from '@/lib/utils'

// The per-status AI action label. Each funnel stage has its own super-power.
const AI_ACTION_LABEL = {
  ideation: 'Sintetizar ideias',
  scoping: 'Gerar checklist',
  production: 'Escrever legendas',
  scheduled: 'Melhor horário',
  published: 'Resumir',
  retrospective: 'Resumir',
  done: 'Resumir',
}

// A gradient-tinted card showing the Claude summary for the current status,
// with a "Regenerar" button and the status's contextual AI action.
export default function AiSummaryCard({
  status,
  summary,
  onSummarize,
  onAiAction,
  summarizing = false,
  acting = false,
}) {
  const m = statusMeta(status)
  const actionLabel = AI_ACTION_LABEL[status] || 'Resumir'

  return (
    <div
      className="relative overflow-hidden rounded-2xl border p-5 animate-rise"
      style={{
        borderColor: `${m.color}33`,
        background: `linear-gradient(135deg, ${m.color}12, ${m.color}05 55%, transparent)`,
      }}
    >
      <div className="pointer-events-none absolute -right-8 -top-10 size-36 rounded-full opacity-[0.10]" style={{ background: m.color }} />

      <div className="relative flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2.5">
          <div
            className="flex size-9 items-center justify-center rounded-xl shadow-sm"
            style={{ background: m.color, color: '#fff' }}
          >
            <Sparkles size={18} strokeWidth={2.4} />
          </div>
          <div>
            <p className="text-[11px] font-bold uppercase tracking-[0.14em]" style={{ color: m.color }}>
              Resumo IA
            </p>
            <p className="text-xs font-medium text-ink-muted">Contexto de “{m.label}”</p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" onClick={() => onSummarize?.()} disabled={summarizing}>
            {summarizing ? <Spinner size={14} /> : <RefreshCw size={14} />}
            Regenerar
          </Button>
          <Button
            size="sm"
            onClick={() => onAiAction?.()}
            disabled={acting}
            style={{ background: `linear-gradient(135deg, ${m.color}, ${m.color}cc)` }}
            className="text-white shadow-[0_8px_20px_-8px_rgba(0,0,0,0.4)] hover:brightness-105"
          >
            {acting ? <Spinner size={14} className="border-white/30 border-t-white" /> : <Wand2 size={14} />}
            {actionLabel}
          </Button>
        </div>
      </div>

      <div className="relative mt-4">
        {summarizing && !summary ? (
          <div className="flex items-center gap-2 text-sm text-ink-muted">
            <Spinner size={16} /> Pensando…
          </div>
        ) : summary ? (
          <p className={cn('whitespace-pre-wrap text-[15px] leading-relaxed text-ink', summarizing && 'opacity-60')}>
            {summary}
          </p>
        ) : (
          <div className="rounded-xl border border-dashed bg-surface/50 px-4 py-5 text-center" style={{ borderColor: `${m.color}40` }}>
            <Sparkles size={22} className="mx-auto mb-1.5" style={{ color: m.color }} />
            <p className="text-sm font-semibold text-ink">Sem resumo ainda</p>
            <p className="mt-0.5 text-xs text-ink-muted">
              Deixe a IA resumir este ticket no contexto de “{m.label}”.
            </p>
          </div>
        )}
      </div>
    </div>
  )
}
