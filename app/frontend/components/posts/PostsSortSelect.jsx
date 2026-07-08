import { ArrowDownUp } from 'lucide-react'
import { OptionSelect } from '@/components/ui/option-select'

// Sort control for the "Publicações" list. Distinct from the shared filter bar:
// it only reorders the list query (recent/oldest/views/engagement). Sits in a
// compact right-aligned header row above the post grid.
const OPTIONS = [
  { value: 'recent', label: 'Mais recentes' },
  { value: 'oldest', label: 'Mais antigas' },
  { value: 'views', label: 'Mais visualizações' },
  { value: 'engagement', label: 'Maior engajamento' },
]

export default function PostsSortSelect({ value, onChange }) {
  return (
    <div className="flex items-center gap-2">
      <span className="inline-flex items-center gap-1.5 text-[13px] font-semibold text-ink-secondary">
        <ArrowDownUp size={14} strokeWidth={2.3} />
        Ordenar
      </span>
      <OptionSelect
        value={value}
        onChange={(v) => onChange(v || 'recent')}
        placeholder="Mais recentes"
        options={OPTIONS}
      />
    </div>
  )
}
