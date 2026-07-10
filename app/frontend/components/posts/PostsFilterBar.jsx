import { useTranslation } from 'react-i18next'
import { FilterBar } from '@/components/ui/filter-bar'
import { CHANNEL_META, POST_STATUS_META } from '@/lib/constants'

// Filter options derive straight from the shared metadata maps so the pills
// carry each network's / status' brand color + icon.
const NETWORK_OPTIONS = Object.entries(CHANNEL_META).map(([value, m]) => ({ value, label: m.label, color: m.color, icon: m.icon }))
const STATUS_OPTIONS = Object.entries(POST_STATUS_META).map(([value, m]) => ({ value, label: m.label, color: m.color, icon: m.icon }))

// The shared `filters` object is the flat API shape (`client_id`, `project_id`,
// `providers`, `status`, `from`, `to`). The period pill is derived: filters carry
// a concrete `from`, so we reflect which window it corresponds to. Unset → the
// pill reads its placeholder ("Últimos 30 dias", the backend's own default).
function periodFor(from) {
  if (!from) return undefined
  const days = Math.round((Date.now() - new Date(from).getTime()) / 864e5)
  if (days <= 7) return '7'
  if (days <= 30) return '30'
  return '90'
}

// The one filter row above both tabs (shared — it drives the performance overview
// and the post list alike). Built on the declarative `FilterBar` primitive; each
// control patches the flat API-shaped `filters` object. `leading` carries the tabs.
export default function PostsFilterBar({ filters, setFilters, leading }) {
  const { t } = useTranslation('posts')

  const periodOptions = [
    { value: '7', label: t('filters.last7Days') },
    { value: '30', label: t('filters.last30Days') },
    { value: '90', label: t('filters.last90Days') },
  ]

  const filterDefs = [
    { key: 'client', type: 'client', label: t('filters.client') },
    { key: 'campaign', type: 'project', label: t('filters.campaign') },
    { key: 'network', type: 'options', label: t('filters.network'), options: NETWORK_OPTIONS },
    { key: 'status', type: 'options', label: t('filters.status'), options: STATUS_OPTIONS },
    { key: 'period', type: 'options', label: t('filters.period'), options: periodOptions, placeholder: t('filters.last30Days') },
  ]

  const values = {
    client: filters.client_id,
    campaign: filters.project_id,
    network: filters.providers?.[0],
    status: filters.status?.[0],
    period: periodFor(filters.from),
  }

  const onChange = (key, value) => {
    setFilters((f) => {
      switch (key) {
        case 'client':   return { ...f, client_id: value || undefined }
        case 'campaign': return { ...f, project_id: value || undefined }
        case 'network':  return { ...f, providers: value ? [value] : undefined }
        case 'status':   return { ...f, status: value ? [value] : undefined }
        case 'period': {
          const days = Number(value)
          const from = value ? new Date(Date.now() - days * 864e5).toISOString().slice(0, 10) : undefined
          return { ...f, from, to: undefined }
        }
        default: return f
      }
    })
  }

  return (
    <FilterBar
      leading={leading}
      filters={filterDefs}
      values={values}
      onChange={onChange}
      onClear={() => setFilters({})}
    />
  )
}
