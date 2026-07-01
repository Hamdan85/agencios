import { X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

// Contextual action bar that takes the place of the filter bar while a
// multi-select is active: the selected count, the caller's action(s), and a
// "clear selection" button. Mirrors FilterBar's outer spacing so swapping one
// for the other in the same slot is seamless.
export function SelectionBar({ count, total, onClear, onSelectAll, children, className }) {
  // Offer "select all" only when there are more matching rows than are selected.
  const canSelectAll = onSelectAll && total != null && count < total

  return (
    <div className={cn(
      'mb-4 flex items-center gap-2.5 rounded-xl border border-brand/30 bg-brand/[0.06] px-3 py-2',
      className,
    )}>
      <span className="grid size-6 shrink-0 place-items-center rounded-md bg-brand text-[12px] font-bold text-white">
        {count}
      </span>
      <span className="text-[13px] font-semibold text-ink">
        {count === 1 ? '1 selecionado' : `${count} selecionados`}
      </span>
      {canSelectAll && (
        <Button variant="ghost" size="sm" className="gap-1 font-semibold text-brand" onClick={onSelectAll}>
          Selecionar todos ({total})
        </Button>
      )}

      <div className="ml-auto flex items-center gap-1.5">
        {children}
        <Button variant="ghost" size="sm" className="gap-1 text-ink-muted" onClick={onClear}>
          <X size={14} /> Limpar seleção
        </Button>
      </div>
    </div>
  )
}

export default SelectionBar
