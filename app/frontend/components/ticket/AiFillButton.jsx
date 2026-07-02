import { RefreshCw } from 'lucide-react'
import { Spinner } from '@/components/ui/feedback'
import { Tooltip, TooltipTrigger, TooltipContent } from '@/components/ui/tooltip'

// A deliberately subtle, outlined icon button in the header's top-right that
// regenerates the CURRENT stage's fields from everything produced in the earlier
// stages. Icon-only + tooltip keeps it out of the way — it's not a primary,
// click-all-the-time action.
export default function AiFillButton({ onClick, acting = false, color = '#6366F1' }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <button
          type="button"
          onClick={() => onClick?.()}
          disabled={acting}
          aria-label="Atualizar campos com IA"
          className="inline-flex size-8 items-center justify-center rounded-lg border border-border-strong text-ink-muted transition hover:bg-surface-muted hover:text-ink disabled:opacity-50"
        >
          {acting ? <Spinner size={14} /> : <RefreshCw size={14} style={{ color }} />}
        </button>
      </TooltipTrigger>
      <TooltipContent>
        Regera os campos desta etapa com IA, a partir de tudo o que foi feito nas etapas anteriores.
      </TooltipContent>
    </Tooltip>
  )
}
