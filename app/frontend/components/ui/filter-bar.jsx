import { useEffect, useRef, useState } from 'react'
import { SlidersHorizontal, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { SearchInput } from '@/components/ui/search-input'
import { FilterSheet, FilterField } from '@/components/ui/filter-sheet'
import { ProjectSelect, ClientSelect, AssigneeSelect } from '@/components/ui/entity-select'
import { OptionSelect } from '@/components/ui/option-select'
import { cn } from '@/lib/utils'

// Renders one filter control from its descriptor, in the right variant for the
// surface (a compact `pill` on desktop, a full-width `field` in the mobile sheet).
function Control({ ctrl, value, onChange, variant }) {
  const isField = variant === 'field'
  const common = { value, onChange, variant, placeholder: ctrl.label }
  switch (ctrl.type) {
    case 'project':  return <ProjectSelect {...common} listParams={ctrl.listParams} />
    case 'client':   return <ClientSelect {...common} />
    case 'assignee': return <AssigneeSelect {...common} />
    default:         return <OptionSelect value={value} onChange={onChange} placeholder={ctrl.label} options={ctrl.options} fullWidth={isField} />
  }
}

// The one filter bar for every listing: an optional title search plus a
// declarative set of filters — ALL on a single row. On desktop the filters sit
// inline next to the search; on mobile they collapse into a "Filtros" bottom
// sheet (the search stays inline). Drive it with a `filters` spec so each listing
// only declares WHAT to filter, never re-implements the layout or the pickers.
//
//   filters = [
//     { key: 'project_id', type: 'project', label: 'Campanha' },
//     { key: 'status', type: 'options', label: 'Status', options: [...] },
//   ]
//
export function FilterBar({
  search,            // boolean | undefined — whether to show the search field
  searchValue = '',  // current persisted query (source of truth; e.g. filters.q)
  onSearch,          // (value|undefined) => void — called debounced
  searchPlaceholder = 'Buscar…',
  filters = [],
  values = {},
  onChange,          // (key, value) => void
  onClear,           // () => void — clears the filter values (not the search)
  leading,           // optional node rendered first (e.g. tabs)
  trailing,          // optional node rendered last on desktop (e.g. an action)
  className,
}) {
  const showSearch = search ?? !!onSearch
  const [q, setQ] = useState(searchValue || '')

  // Adopt external resets (e.g. "clear all") without fighting typing.
  useEffect(() => { setQ(searchValue || '') }, [searchValue])

  // Debounce the text search into the query.
  const onSearchRef = useRef(onSearch)
  onSearchRef.current = onSearch
  useEffect(() => {
    const t = setTimeout(() => {
      if ((q || '') !== (searchValue || '')) onSearchRef.current?.(q || undefined)
    }, 300)
    return () => clearTimeout(t)
  }, [q]) // eslint-disable-line react-hooks/exhaustive-deps

  const activeCount = filters.filter((f) => {
    const v = values[f.key]
    return v != null && v !== ''
  }).length

  const set = (key) => (v) => onChange?.(key, v)

  return (
    <div className={cn('mb-4 flex items-center gap-2.5', className)}>
      {leading}

      {/* Search shrinks to whatever is left — the filters always stay fully
          visible (never cropped / scrolled off) on desktop. */}
      {showSearch && (
        <SearchInput
          value={q}
          onChange={setQ}
          placeholder={searchPlaceholder}
          className="min-w-0 flex-1"
        />
      )}

      {/* Desktop: all filters on the same row, at their natural width */}
      {filters.length > 0 && (
        <div className="hidden shrink-0 items-center gap-2 lg:flex">
          <span className="flex shrink-0 items-center gap-1.5 text-[12px] font-bold uppercase tracking-wider text-ink-muted">
            <SlidersHorizontal size={14} strokeWidth={2.4} /> Filtros
          </span>
          {filters.map((f) => (
            <Control key={f.key} ctrl={f} value={values[f.key]} onChange={set(f.key)} variant="pill" />
          ))}
          {activeCount > 0 && (
            <Button variant="ghost" size="sm" className="shrink-0 gap-1 text-ink-muted" onClick={onClear}>
              <X size={14} /> Limpar ({activeCount})
            </Button>
          )}
          {trailing && <div className="shrink-0">{trailing}</div>}
        </div>
      )}

      {/* Mobile: filters condensed into a bottom sheet (search stays inline) */}
      {filters.length > 0 && (
        <FilterSheet count={activeCount} onClear={onClear} className="lg:hidden">
          {filters.map((f) => (
            <FilterField key={f.key} label={f.label}>
              <Control ctrl={f} value={values[f.key]} onChange={set(f.key)} variant="field" />
            </FilterField>
          ))}
        </FilterSheet>
      )}

      {/* When there are no filters, still allow a trailing desktop action. */}
      {filters.length === 0 && trailing}
    </div>
  )
}

export default FilterBar
