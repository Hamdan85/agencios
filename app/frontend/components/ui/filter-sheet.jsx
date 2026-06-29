import { useState } from 'react'
import { SlidersHorizontal, X } from 'lucide-react'
import { Sheet, SheetContent, SheetTitle } from '@/components/ui/sheet'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

// Mobile filter affordance: a compact "Filtros" button (with an active-count
// badge) that opens a bottom sheet holding the filter controls stacked
// full-width. Pages render their filters inline on desktop and route them
// through this on mobile — so this whole thing is meant to live under `lg:hidden`.
//
//   <FilterSheet count={n} onClear={...}>
//     <FilterField label="Projeto"><AsyncCombobox variant="field" …/></FilterField>
//     …
//   </FilterSheet>
export function FilterSheet({ count = 0, onClear, children, title = 'Filtros', className }) {
  const [open, setOpen] = useState(false)

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className={cn(
          'relative flex h-9 shrink-0 items-center gap-1.5 rounded-xl border px-3 text-[13px] font-semibold transition-colors',
          count > 0
            ? 'border-brand/40 bg-brand-soft text-brand'
            : 'border-border bg-surface-muted text-ink-secondary hover:border-brand/40',
          className,
        )}
      >
        <SlidersHorizontal size={15} strokeWidth={2.3} />
        Filtros
        {count > 0 && (
          <span className="flex size-5 items-center justify-center rounded-full bg-brand text-[11px] font-bold text-white">
            {count}
          </span>
        )}
      </button>

      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent side="bottom">
          <div className="flex items-center justify-between border-b border-border px-5 py-4">
            <SheetTitle className="text-lg">{title}</SheetTitle>
            <button
              type="button"
              aria-label="Fechar"
              onClick={() => setOpen(false)}
              className="rounded-lg p-1 text-ink-muted transition hover:bg-surface-muted"
            >
              <X size={18} />
            </button>
          </div>

          <div className="flex-1 space-y-4 overflow-y-auto px-5 py-4">
            {children}
          </div>

          <div className="flex items-center gap-3 border-t border-border px-5 py-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
            {onClear && (
              <Button
                type="button"
                variant="ghost"
                className="flex-1"
                disabled={count === 0}
                onClick={onClear}
              >
                Limpar{count > 0 ? ` (${count})` : ''}
              </Button>
            )}
            <Button type="button" className="flex-1" onClick={() => setOpen(false)}>
              Ver resultados
            </Button>
          </div>
        </SheetContent>
      </Sheet>
    </>
  )
}

// A labelled row for a control inside the filter sheet.
export function FilterField({ label, children }) {
  return (
    <div className="space-y-1.5">
      <span className="text-[12px] font-bold uppercase tracking-wider text-ink-muted">{label}</span>
      {children}
    </div>
  )
}

export default FilterSheet
