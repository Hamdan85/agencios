import { statusMeta } from '@/lib/constants'
import { Markdown } from '@/components/ui/markdown'
import { Sparkles } from 'lucide-react'

// A gradient-tinted card that shows the Claude summary for the current status.
// It is display-only: the summary regenerates automatically whenever the stage's
// fields change (once, server-side). The action that rewrites the stage's fields
// ("Atualizar com IA") lives in the field cards, not here.
export default function AiSummaryCard({ status, summary }) {
  const m = statusMeta(status)

  return (
    <div
      className="relative overflow-hidden rounded-2xl border p-5 animate-rise"
      style={{
        borderColor: `${m.color}33`,
        background: `linear-gradient(135deg, ${m.color}12, ${m.color}05 55%, transparent)`,
      }}
    >
      <div className="pointer-events-none absolute -right-8 -top-10 size-36 rounded-full opacity-[0.10]" style={{ background: m.color }} />

      <div className="relative flex items-center gap-2.5">
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

      <div className="relative mt-4">
        {summary ? (
          <Markdown className="text-[15px]">{summary}</Markdown>
        ) : (
          <div className="rounded-xl border border-dashed bg-surface/50 px-4 py-5 text-center" style={{ borderColor: `${m.color}40` }}>
            <Sparkles size={22} className="mx-auto mb-1.5" style={{ color: m.color }} />
            <p className="text-sm font-semibold text-ink">Sem resumo ainda</p>
            <p className="mt-0.5 text-xs text-ink-muted">
              O resumo é gerado automaticamente conforme você preenche esta etapa.
            </p>
          </div>
        )}
      </div>
    </div>
  )
}
