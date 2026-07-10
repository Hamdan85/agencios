import { useTranslation } from 'react-i18next'
import { ArrowDownUp } from 'lucide-react'
import { OptionSelect } from '@/components/ui/option-select'

// Sort control for the "Publicações" list. Distinct from the shared filter bar:
// it only reorders the list query (recent/oldest/views/engagement). Sits in a
// compact right-aligned header row above the post grid.
export default function PostsSortSelect({ value, onChange }) {
  const { t } = useTranslation('posts')
  const options = [
    { value: 'recent', label: t('sort.recent') },
    { value: 'oldest', label: t('sort.oldest') },
    { value: 'views', label: t('sort.views') },
    { value: 'engagement', label: t('sort.engagement') },
  ]
  return (
    <div className="flex items-center gap-2">
      <span className="inline-flex items-center gap-1.5 text-[13px] font-semibold text-ink-secondary">
        <ArrowDownUp size={14} strokeWidth={2.3} />
        {t('sort.label')}
      </span>
      <OptionSelect
        value={value}
        onChange={(v) => onChange(v || 'recent')}
        placeholder={t('sort.recent')}
        options={options}
      />
    </div>
  )
}
