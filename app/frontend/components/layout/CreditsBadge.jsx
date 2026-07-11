import { Link } from 'react-router-dom'
import { Coins, Infinity as InfinityIcon } from 'lucide-react'
import { useCurrentUser } from '@/hooks/useAuth'
import { SectionLabel } from '@/components/ui/section-label'
import { num } from '@/lib/formatters'
import { useTranslation } from 'react-i18next'

// Compact wallet indicator in the sidebar. Reads the balance off `/me`
// (workspace.credits_available) so it's always fresh with the session, and
// links to /assinatura where credits can be topped up. Shows "∞" only when
// credits are truly untracked (unlimited godfathered → credits_available null);
// capped godfathered workspaces show their remaining balance like everyone else.
export default function CreditsBadge({ onNavigate }) {
  const { t } = useTranslation('billing')
  const { data: me } = useCurrentUser()
  const ws = me?.workspace
  if (!ws) return null

  const unlimited = ws.credits_available == null
  const value = Number(ws.credits_available ?? 0)
  const low = !unlimited && value <= 10

  return (
    <Link
      to="/assinatura"
      onClick={onNavigate}
      className="group flex items-center gap-2.5 rounded-xl border border-white/10 bg-white/[0.05] px-2.5 py-2 transition hover:bg-white/[0.09]"
    >
      <span
        className="flex size-7 items-center justify-center rounded-lg"
        style={{ background: low ? 'rgba(244,63,94,0.16)' : 'rgba(245,158,11,0.16)', color: low ? '#F43F5E' : '#F59E0B' }}
      >
        <Coins size={15} strokeWidth={2.3} />
      </span>
      <span className="min-w-0 flex-1">
        <SectionLabel as="span" className="block text-[10px] text-white/40">{t('credits.title')}</SectionLabel>
        <span className={low ? 'block text-sm font-extrabold text-[#FDA4AF]' : 'block text-sm font-extrabold text-white'}>
          {unlimited ? <InfinityIcon size={16} className="inline align-[-2px]" /> : num(value)}
        </span>
      </span>
    </Link>
  )
}
