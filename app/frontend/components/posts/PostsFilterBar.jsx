import { useTranslation } from 'react-i18next'
import { FilterBar } from '@/components/ui/filter-bar'
import { CHANNEL_META, POST_STATUS_META } from '@/lib/constants'

// Filter options derive straight from the shared metadata maps so the pills
// carry each network's / status' brand color + icon.
const NETWORK_OPTIONS = Object.entries(CHANNEL_META).map(([value, m]) => ({ value, label: m.label, color: m.color, icon: m.icon }))
const STATUS_OPTIONS = Object.entries(POST_STATUS_META).map(([value, m]) => ({ value, label: m.label, color: m.color, icon: m.icon }))

// The one filter row above both tabs (shared — it drives the performance overview
// and the post list alike). Built on the declarative `FilterBar` primitive; each
// control patches the flat URL-synced filter object (`client_id` / `project_id` /
// `network` / `status` / `period`) — the page expands it into the API query
// shape. Unset period → the pill reads its placeholder ("Últimos 30 dias", the
// backend's own default). `leading` carries the tabs.
export default function PostsFilterBar({ filters, setFilters, leading }) {
  const { t } = useTranslation('posts')

  const periodOptions = [
    { value: '7', label: t('filters.last7Days') },
    { value: '30', label: t('filters.last30Days') },
    { value: '90', label: t('filters.last90Days') },
  ]

  const filterDefs = [
    { key: 'client_id', type: 'client', label: t('filters.client') },
    { key: 'project_id', type: 'project', label: t('filters.campaign') },
    { key: 'network', type: 'options', label: t('filters.network'), options: NETWORK_OPTIONS },
    { key: 'status', type: 'options', label: t('filters.status'), options: STATUS_OPTIONS },
    { key: 'period', type: 'options', label: t('filters.period'), options: periodOptions, placeholder: t('filters.last30Days') },
  ]

  const onChange = (key, value) => setFilters((f) => ({ ...f, [key]: value || undefined }))

  return (
    <FilterBar
      leading={leading}
      filters={filterDefs}
      values={filters}
      onChange={onChange}
      onClear={() => setFilters({})}
    />
  )
}
