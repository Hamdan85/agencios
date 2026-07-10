import { useTranslation } from 'react-i18next'
import { STATUS_META, CHANNEL_META, CREATIVE_TYPE_META } from '@/lib/constants'
import { FilterBar } from '@/components/ui/filter-bar'

const FILTER_KEYS = ['status', 'assignee_id', 'channel', 'creative_type']

// Filter bar for a single project's ticket list — title search + status /
// assignee / channel / type, all on one line (bottom sheet on mobile). Project
// and client filters are implicit on a single-project page, so they're omitted.
export function TicketFilters({ filters, onChange }) {
  const { t } = useTranslation('ticket')
  const statusOptions = Object.entries(STATUS_META).map(([k, m]) => ({ value: k, label: m.label, color: m.color, icon: m.icon }))
  const channelOptions = Object.entries(CHANNEL_META).map(([k, m]) => ({ value: k, label: m.label, icon: m.icon, color: m.color }))
  const creativeOptions = Object.entries(CREATIVE_TYPE_META).map(([k, m]) => ({ value: k, label: m.label, icon: m.icon, color: m.color }))

  const spec = [
    { key: 'status', type: 'options', label: t('filters.status'), options: statusOptions },
    { key: 'assignee_id', type: 'assignee', label: t('filters.assignee') },
    { key: 'channel', type: 'options', label: t('filters.channel'), options: channelOptions },
    { key: 'creative_type', type: 'options', label: t('filters.type'), options: creativeOptions },
  ]

  const clearFilters = () => {
    const next = { ...filters }
    FILTER_KEYS.forEach((k) => delete next[k])
    onChange(next)
  }

  return (
    <FilterBar
      search
      searchValue={filters?.q || ''}
      onSearch={(v) => onChange({ ...filters, q: v })}
      searchPlaceholder={t('filters.searchPlaceholder')}
      filters={spec}
      values={filters || {}}
      onChange={(key, value) => onChange({ ...filters, [key]: value })}
      onClear={clearFilters}
    />
  )
}

export default TicketFilters
