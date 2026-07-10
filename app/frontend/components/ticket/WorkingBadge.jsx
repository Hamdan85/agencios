import { Loader2 } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'

// "Working" indicator for a ticket executing on autopilot (GO mode) — the ticket
// is walking itself (generating creatives + scheduling posts). Shown on the board
// card and the list row while `ticket.autopilot_running` is true.
export function WorkingBadge({ className }) {
  const { t } = useTranslation('ticket')
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1 rounded-md bg-brand/12 px-1.5 py-0.5 text-[10.5px] font-bold text-brand',
        className,
      )}
    >
      <Loader2 size={11} strokeWidth={2.6} className="animate-spin" />
      {t('workingBadge')}
    </span>
  )
}

export default WorkingBadge
