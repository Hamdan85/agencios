import { Wand2 } from 'lucide-react'
import { Spinner } from '@/components/ui/feedback'

// A deliberately subtle action that regenerates the CURRENT stage's fields from
// everything produced in the earlier stages. It lives in the field cards (not
// the AI summary card) because it rewrites the ticket's fields — not the summary.
export default function AiFillButton({ onClick, acting = false, color = '#6366F1' }) {
  return (
    <button
      type="button"
      onClick={() => onClick?.()}
      disabled={acting}
      title="Regenera os campos desta etapa com base em tudo o que foi feito nas etapas anteriores"
      className="inline-flex items-center gap-1.5 rounded-lg px-2 py-1 text-xs font-semibold text-ink-muted transition hover:bg-surface-muted hover:text-ink disabled:opacity-50"
    >
      {acting ? <Spinner size={13} /> : <Wand2 size={13} style={{ color }} />}
      Atualizar com IA
    </button>
  )
}
