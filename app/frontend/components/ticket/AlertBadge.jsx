import { AlertTriangle } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'

// Shown when a ticket is "in alert" — something broke at posting time (a failed
// publish). The reason is the tooltip; a generated task tracks the fix.
export function AlertBadge({ reason, className }) {
  const { t } = useTranslation('ticket')
  return (
    <span
      title={reason || undefined}
      className={cn(
        'inline-flex items-center gap-1 rounded-md bg-danger/12 px-1.5 py-0.5 text-[10.5px] font-bold text-danger',
        className,
      )}
    >
      <AlertTriangle size={11} strokeWidth={2.6} />
      {t('alertBadge')}
    </span>
  )
}

export default AlertBadge
