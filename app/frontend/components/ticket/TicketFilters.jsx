import { SlidersHorizontal, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import { STATUS_META, CHANNEL_META, CREATIVE_TYPE_META } from '@/lib/constants'
import { useWorkspaceMembers } from '@/hooks/useData'
import { Button } from '@/components/ui/button'
import { FilterSheet, FilterField } from '@/components/ui/filter-sheet'
import {
  Select, SelectTrigger, SelectValue, SelectContent, SelectItem,
} from '@/components/ui/select'

const ALL = '__all__'
const FILTER_KEYS = ['status', 'assignee_id', 'channel', 'creative_type']

function FilterSelect({ value, onChange, placeholder, options, fullWidth }) {
  return (
    <Select value={value || ALL} onValueChange={(v) => onChange(v === ALL ? undefined : v)}>
      <SelectTrigger className={cn('h-9 gap-1.5 text-[13px]', fullWidth ? 'w-full' : 'w-auto min-w-[130px]')}>
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

// Compact filter bar for a list of tickets scoped to a single project. Project
// and client filters are intentionally omitted — they are implicit on a
// single-project page. Inline on desktop; condensed into a bottom sheet on mobile.
export function TicketFilters({ filters, onChange }) {
  const members = useWorkspaceMembers()

  const statusOptions = Object.entries(STATUS_META).map(([k, m]) => ({ value: k, label: m.label, color: m.color, icon: m.icon }))
  const memberOptions = (members.data || []).map((m) => ({ value: m.id, label: m.name }))
  const channelOptions = Object.entries(CHANNEL_META).map(([k, m]) => ({ value: k, label: m.label, icon: m.icon, color: m.color }))
  const creativeOptions = Object.entries(CREATIVE_TYPE_META).map(([k, m]) => ({ value: k, label: m.label, icon: m.icon, color: m.color }))

  const set = (key) => (value) => onChange({ ...filters, [key]: value })
  const activeCount = FILTER_KEYS.filter((k) => filters?.[k]).length

  const controls = [
    { key: 'status', label: 'Status', options: statusOptions },
    { key: 'assignee_id', label: 'Responsável', options: memberOptions },
    { key: 'channel', label: 'Canal', options: channelOptions },
    { key: 'creative_type', label: 'Tipo', options: creativeOptions },
  ]

  return (
    <div className="mb-4 flex items-center gap-2.5">
      {/* Desktop: inline */}
      <div className="hidden items-center gap-2.5 overflow-x-auto pb-1 no-scrollbar lg:flex">
        <span className="flex shrink-0 items-center gap-1.5 text-[12px] font-bold uppercase tracking-wider text-ink-muted">
          <SlidersHorizontal size={14} strokeWidth={2.4} /> Filtros
        </span>
        {controls.map((c) => (
          <FilterSelect key={c.key} value={filters?.[c.key]} onChange={set(c.key)} placeholder={c.label} options={c.options} />
        ))}
        {activeCount > 0 && (
          <Button variant="ghost" size="sm" className="shrink-0 gap-1 text-ink-muted" onClick={() => onChange({})}>
            <X size={14} /> Limpar ({activeCount})
          </Button>
        )}
      </div>

      {/* Mobile: bottom sheet */}
      <FilterSheet count={activeCount} onClear={() => onChange({})} className="lg:hidden">
        {controls.map((c) => (
          <FilterField key={c.key} label={c.label}>
            <FilterSelect fullWidth value={filters?.[c.key]} onChange={set(c.key)} placeholder={c.label} options={c.options} />
          </FilterField>
        ))}
      </FilterSheet>
    </div>
  )
}

export default TicketFilters
