import { useEffect, useRef, useState } from 'react'
import { SlidersHorizontal, X, Folder, Building2, User } from 'lucide-react'
import { CHANNEL_META, CREATIVE_TYPE_META } from '@/lib/constants'
import { projectsApi, clientsApi, workspaceApi } from '@/api'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { SearchInput } from '@/components/ui/search-input'
import { AsyncCombobox } from '@/components/ui/async-combobox'
import { FilterSheet, FilterField } from '@/components/ui/filter-sheet'
import {
  Select, SelectTrigger, SelectValue, SelectContent, SelectItem,
} from '@/components/ui/select'

const ALL = '__all__'
const FILTER_KEYS = ['project_id', 'client_id', 'assignee_id', 'channel', 'creative_type']

// Static (small, fixed-list) filter — channel / creative type. `fullWidth`
// stretches the trigger for the stacked mobile filter sheet.
function StaticSelect({ value, onChange, placeholder, options, fullWidth }) {
  return (
    <Select value={value || ALL} onValueChange={(v) => onChange(v === ALL ? undefined : v)}>
      <SelectTrigger className={cn('h-9 shrink-0 gap-1.5 rounded-xl text-[13px]', fullWidth ? 'w-full' : 'w-auto min-w-[124px]')}>
        <SelectValue placeholder={placeholder} />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={ALL}>{placeholder}</SelectItem>
        {options.map((o) => (
          <SelectItem key={o.value} value={String(o.value)}>
            <span className="inline-flex items-center gap-2">
              {o.color && <span className="size-2.5 rounded-full" style={{ background: o.color }} />}
              {o.icon ? <o.icon size={14} strokeWidth={2.3} style={{ color: o.color }} /> : null}
              {o.label}
            </span>
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}

// Filter bar: a title search plus the project / client / assignee / channel /
// type filters. On desktop they sit in a horizontally-scrollable row; on mobile
// they collapse into a single "Filtros" button that opens a bottom sheet.
export function BoardFilters({ filters, onChange }) {
  const set = (key) => (value) => onChange({ ...filters, [key]: value })

  // Debounced title search — pushed into the board filters as `q`.
  const [q, setQ] = useState(filters?.q || '')
  const filtersRef = useRef(filters)
  const onChangeRef = useRef(onChange)
  filtersRef.current = filters
  onChangeRef.current = onChange
  useEffect(() => {
    const t = setTimeout(() => {
      const cur = filtersRef.current
      if ((cur?.q || '') !== (q || '')) onChangeRef.current({ ...cur, q: q || undefined })
    }, 300)
    return () => clearTimeout(t)
  }, [q])

  const channelOptions = Object.entries(CHANNEL_META).map(([k, m]) => ({ value: k, label: m.label, icon: m.icon, color: m.color }))
  const creativeOptions = Object.entries(CREATIVE_TYPE_META).map(([k, m]) => ({ value: k, label: m.label, icon: m.icon, color: m.color }))

  // Shared combobox config so the inline (pill) and sheet (field) variants stay
  // in sync without duplicating the fetch wiring.
  const projectProps = {
    value: filters?.project_id, onChange: set('project_id'), placeholder: 'Projeto', icon: Folder,
    queryKey: ['projects', 'filter'],
    fetchPage: ({ q: term, page }) => projectsApi.list({ q: term, page, per: 20 }),
    mapResponse: (d) => ({ items: d.projects || [], hasMore: d.meta?.has_more }),
    getOption: (p) => ({ value: p.id, label: p.name, color: p.color }),
  }
  const clientProps = {
    value: filters?.client_id, onChange: set('client_id'), placeholder: 'Cliente', icon: Building2,
    queryKey: ['clients', 'filter'],
    fetchPage: ({ q: term, page }) => clientsApi.list({ q: term, page, per: 20 }),
    mapResponse: (d) => ({ items: d.clients || [], hasMore: d.meta?.has_more }),
    getOption: (c) => ({ value: c.id, label: c.name, description: c.company }),
  }
  const assigneeProps = {
    value: filters?.assignee_id, onChange: set('assignee_id'), placeholder: 'Responsável', icon: User,
    queryKey: ['members', 'filter'],
    fetchPage: ({ q: term, page }) => workspaceApi.members({ q: term, page, per: 20 }),
    mapResponse: (d) => ({ items: d.memberships || [], hasMore: d.meta?.has_more }),
    getOption: (m) => ({ value: m.user_id, label: m.name }),
  }

  const filterCount = FILTER_KEYS.filter((k) => filters?.[k]).length
  const activeCount = filterCount + (filters?.q ? 1 : 0)

  const clearAll = () => { setQ(''); onChange({}) }
  const clearFilters = () => {
    const next = { ...filters }
    FILTER_KEYS.forEach((k) => delete next[k])
    onChange(next)
  }

  return (
    <div className="mb-4 flex items-center gap-2.5">
      <SearchInput
        value={q}
        onChange={setQ}
        placeholder="Buscar por título…"
        className="min-w-0 flex-1 lg:w-64 lg:flex-none"
      />

      {/* Desktop: inline scrollable filter row */}
      <div className="hidden min-w-0 flex-1 items-center gap-2.5 overflow-x-auto px-1 py-2 no-scrollbar lg:flex">
        <span className="flex shrink-0 items-center gap-1.5 text-[12px] font-bold uppercase tracking-wider text-ink-muted">
          <SlidersHorizontal size={14} strokeWidth={2.4} /> Filtros
        </span>
        <AsyncCombobox {...projectProps} />
        <AsyncCombobox {...clientProps} />
        <AsyncCombobox {...assigneeProps} />
        <StaticSelect value={filters?.channel} onChange={set('channel')} placeholder="Canal" options={channelOptions} />
        <StaticSelect value={filters?.creative_type} onChange={set('creative_type')} placeholder="Tipo" options={creativeOptions} />
        {activeCount > 0 && (
          <Button variant="ghost" size="sm" className="shrink-0 gap-1 text-ink-muted" onClick={clearAll}>
            <X size={14} /> Limpar ({activeCount})
          </Button>
        )}
      </div>

      {/* Mobile: condensed into a bottom sheet */}
      <FilterSheet count={filterCount} onClear={clearFilters} className="lg:hidden">
        <FilterField label="Projeto"><AsyncCombobox {...projectProps} variant="field" /></FilterField>
        <FilterField label="Cliente"><AsyncCombobox {...clientProps} variant="field" /></FilterField>
        <FilterField label="Responsável"><AsyncCombobox {...assigneeProps} variant="field" /></FilterField>
        <FilterField label="Canal"><StaticSelect fullWidth value={filters?.channel} onChange={set('channel')} placeholder="Canal" options={channelOptions} /></FilterField>
        <FilterField label="Tipo"><StaticSelect fullWidth value={filters?.creative_type} onChange={set('creative_type')} placeholder="Tipo" options={creativeOptions} /></FilterField>
      </FilterSheet>
    </div>
  )
}

export default BoardFilters
