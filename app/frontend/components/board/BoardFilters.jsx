import { useTranslation } from 'react-i18next'
import { CHANNEL_META, CREATIVE_TYPE_META } from '@/lib/constants'
import { FilterBar } from '@/components/ui/filter-bar'

const FILTER_KEYS = ['project_id', 'client_id', 'assignee_id', 'channel', 'creative_type']

// Board filter bar — title search + project / client / assignee / channel / type,
// all on one line (collapsing to a bottom sheet on mobile). Built on the shared
// FilterBar + reusable entity pickers so every listing stays consistent.
export function BoardFilters({ filters, onChange }) {
  const { t } = useTranslation('board')
  const channelOptions = Object.entries(CHANNEL_META).map(([k, m]) => ({ value: k, label: m.label, icon: m.icon, color: m.color }))
  const creativeOptions = Object.entries(CREATIVE_TYPE_META).map(([k, m]) => ({ value: k, label: m.label, icon: m.icon, color: m.color }))

  const spec = [
    { key: 'project_id', type: 'project', label: t('filters.campaign') },
    { key: 'client_id', type: 'client', label: t('filters.client') },
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

export default BoardFilters
