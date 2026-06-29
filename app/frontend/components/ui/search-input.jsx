import { Search, X } from 'lucide-react'
import { cn } from '@/lib/utils'

// A compact search field with a leading icon and a clear button. Controlled —
// debounce at the call site if the value drives a query.
export function SearchInput({ value, onChange, placeholder = 'Buscar…', className, autoFocus }) {
  return (
    <div className={cn('relative flex items-center', className)}>
      <Search size={15} strokeWidth={2.3} className="pointer-events-none absolute left-3 text-ink-faint" />
      <input
        type="text"
        value={value || ''}
        autoFocus={autoFocus}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="h-9 w-full rounded-xl border border-border bg-surface-muted pl-9 pr-8 text-[13px] text-ink outline-none transition-colors placeholder:text-ink-faint focus:border-brand focus:ring-2 focus:ring-brand/20"
      />
      {value ? (
        <button
          type="button"
          aria-label="Limpar busca"
          onClick={() => onChange('')}
          className="absolute right-2 rounded-md p-0.5 text-ink-faint transition hover:bg-surface hover:text-ink"
        >
          <X size={14} />
        </button>
      ) : null}
    </div>
  )
}

export default SearchInput
