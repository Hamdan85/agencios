import { Check, Minus } from 'lucide-react'
import { cn } from '@/lib/utils'

// A square selection checkbox for multi-select list rows / headers. Stops click
// propagation / default so it works nested inside a clickable row or next to a
// <Link>. `indeterminate` renders the "some selected" dash (header use).
export function SelectCheckbox({ checked = false, indeterminate = false, onChange, label = 'Selecionar', className }) {
  const on = checked || indeterminate
  return (
    <button
      type="button"
      role="checkbox"
      aria-checked={indeterminate ? 'mixed' : checked}
      aria-label={label}
      onClick={(e) => { e.stopPropagation(); e.preventDefault(); onChange?.(!checked) }}
      className={cn(
        'grid size-5 shrink-0 place-items-center rounded-md border-2 transition-all active:scale-90',
        on ? 'border-brand bg-brand text-white' : 'border-border text-transparent hover:border-brand/60',
        className,
      )}
    >
      {indeterminate ? <Minus size={13} strokeWidth={3} /> : <Check size={13} strokeWidth={3} />}
    </button>
  )
}

export default SelectCheckbox
