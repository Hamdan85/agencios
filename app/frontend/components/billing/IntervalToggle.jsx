import { cn } from '@/lib/utils'
import { useTranslation } from 'react-i18next'

// Mensal / Anual segmented control for the plan pickers (paywall + billing).
// Controlled: `value` is 'month' | 'year'; `onChange` receives the new interval.
// `discountPercent` renders a small savings pill on the "Anual" segment.
export function IntervalToggle({ value, onChange, discountPercent, className }) {
  const { t } = useTranslation('billing')
  const options = [
    { key: 'month', label: t('plan.monthly') },
    { key: 'year', label: t('plan.annual') },
  ]
  return (
    <div
      role="tablist"
      aria-label={t('intervalToggle.ariaLabel')}
      className={cn(
        'inline-flex items-center gap-1 rounded-full border border-border bg-surface p-1',
        className,
      )}
    >
      {options.map((opt) => {
        const active = value === opt.key
        return (
          <button
            key={opt.key}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() => onChange(opt.key)}
            className={cn(
              'inline-flex items-center gap-1.5 rounded-full px-4 py-1.5 text-sm font-semibold transition',
              active ? 'bg-brand text-white shadow-sm' : 'text-ink-secondary hover:text-ink',
            )}
          >
            {opt.label}
            {opt.key === 'year' && discountPercent > 0 && (
              <span
                className={cn(
                  'rounded-full px-1.5 py-0.5 text-[10px] font-bold leading-none',
                  active ? 'bg-white/25 text-white' : 'bg-emerald/12 text-emerald',
                )}
              >
                -{discountPercent}%
              </span>
            )}
          </button>
        )
      })}
    </div>
  )
}
