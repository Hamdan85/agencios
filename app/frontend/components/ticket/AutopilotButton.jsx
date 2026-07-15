import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useTranslation, Trans } from 'react-i18next'
import { Rocket, Sparkles, AlertTriangle, Wallet } from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { IconTile } from '@/components/ui/icon-tile'
import { InlineSpinner } from '@/components/ui/feedback'
import i18n from '@/i18n'

// Human labels for a run's state (the chip while it walks itself). Resolved
// lazily (getters) so they follow the active locale.
const RUN_STATE_LABEL = {
  get pending() { return i18n.t('ticket:autopilot.runState.pending') },
  get scoping() { return i18n.t('ticket:autopilot.runState.scoping') },
  get generating() { return i18n.t('ticket:autopilot.runState.generating') },
  get awaiting_generation() { return i18n.t('ticket:autopilot.runState.awaiting_generation') },
  get publishing() { return i18n.t('ticket:autopilot.runState.publishing') },
  get running() { return i18n.t('ticket:autopilot.runState.running') },
}

const KIND_LABEL = {
  get video() { return i18n.t('ticket:creatives.kinds.video.label') },
  get image() { return i18n.t('ticket:creatives.kinds.image.label') },
  get carousel() { return i18n.t('ticket:creatives.kinds.carousel.label') },
}

// The "GO" action — estimates the credit cost, asks the user to confirm (once in
// motion the run generates everything and spends the credits), and on a shortfall
// points them to buy more. Data-source-agnostic: the ticket drawer and the project
// page both drive it via the same props.
//
// Props:
//   run        — { active, state } or null (an in-flight run shows a chip instead)
//   estimating — bool, the estimate request is pending
//   starting   — bool, the start request is pending
//   onEstimate — async () => estimate payload
//   onStart    — () => void (launch the run)
//   label      — button text (default "GO")
export default function AutopilotButton({ run, estimating, starting, onEstimate, onStart, label = 'GO' }) {
  const { t } = useTranslation('ticket')
  const navigate = useNavigate()
  const [open, setOpen] = useState(false)
  const [estimate, setEstimate] = useState(null)

  if (run?.active) {
    return (
      <span className="inline-flex items-center gap-2 rounded-xl border border-brand/30 bg-brand-soft px-3 py-1.5 text-xs font-bold text-brand">
        <InlineSpinner size={13} />
        {RUN_STATE_LABEL[run.state] || t('autopilot.runState.running')}
      </span>
    )
  }

  const openEstimate = async () => {
    try {
      const est = await onEstimate()
      setEstimate(est || null)
      setOpen(true)
    } catch {
      /* error toast handled by the mutation */
    }
  }

  const confirm = () => {
    onStart()
    setOpen(false)
  }

  const shortfall = estimate?.shortfall || 0
  const blocked = estimate && !estimate.eligible
  const breakdown = (estimate?.tickets || []).flatMap((t) => t.breakdown || [])

  return (
    <>
      <Button
        size="sm"
        onClick={openEstimate}
        disabled={estimating}
        className="text-white"
        style={{ background: 'linear-gradient(135deg, #7C3AED, #EC4899)' }}
      >
        {estimating ? <InlineSpinner size={14} /> : <Rocket size={14} />}
        {label}
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
          <DialogHeader>
            <IconTile icon={Rocket} tint="1A" className="mb-1 size-11" iconSize={22} />
            <DialogTitle>{t('autopilot.title')}</DialogTitle>
            <DialogDescription>
              {t('autopilot.description')}
            </DialogDescription>
          </DialogHeader>

          {estimate && (
            <div className="space-y-3 text-sm">
              {breakdown.length > 0 && (
                <div className="rounded-2xl border border-border bg-surface-muted/50 p-3">
                  {/* A whole-campaign run can list dozens of items — keep the
                      line items scrollable so the Total and footer stay in view. */}
                  <div className="max-h-56 space-y-0.5 overflow-y-auto">
                    {breakdown.map((b, i) => (
                      <div key={i} className="flex items-center justify-between py-0.5">
                        <span className="text-ink-secondary">{KIND_LABEL[b.kind] || b.type}</span>
                        <span className="font-semibold">
                          {b.existing ? t('autopilot.alreadyGenerated') : b.credits === 0 ? t('autopilot.included') : t('autopilot.credits', { count: b.credits })}
                        </span>
                      </div>
                    ))}
                  </div>
                  <div className="mt-2 flex items-center justify-between border-t border-border pt-2 font-bold">
                    <span>{t('autopilot.total')}</span>
                    <span>{t('autopilot.credits', { count: estimate.total_credits })}</span>
                  </div>
                </div>
              )}

              <div className="flex items-center justify-between text-xs text-ink-muted">
                <span className="inline-flex items-center gap-1.5"><Wallet size={13} /> {t('autopilot.balance')}</span>
                <span className="font-semibold">{estimate.unlimited ? t('autopilot.unlimited') : t('autopilot.credits', { count: estimate.available })}</span>
              </div>

              {blocked && (
                <div className="flex items-start gap-2 rounded-xl bg-danger/10 p-3 text-xs font-semibold text-danger">
                  <AlertTriangle size={15} className="mt-0.5 shrink-0" />
                  <span>
                    {t('autopilot.blocked', { titles: (estimate.blocking_tickets || []).map((bt) => bt.title).join(', ') })}
                  </span>
                </div>
              )}

              {!blocked && shortfall > 0 && (
                <div className="flex items-start gap-2 rounded-xl bg-amber-500/10 p-3 text-xs font-semibold text-amber-600">
                  <AlertTriangle size={15} className="mt-0.5 shrink-0" />
                  <span>{t('autopilot.shortfall', { count: shortfall })}</span>
                </div>
              )}

              {estimate?.has_pending_video && (
                <div className="flex items-start gap-2 rounded-xl bg-sky-500/10 p-3 text-xs font-medium text-sky-700">
                  <AlertTriangle size={15} className="mt-0.5 shrink-0" />
                  <span>
                    <Trans t={t} i18nKey="autopilot.pendingVideo" components={{ strong: <strong /> }} />
                  </span>
                </div>
              )}
            </div>
          )}

          <DialogFooter>
            <Button variant="ghost" onClick={() => setOpen(false)} disabled={starting}>{t('actions.cancel')}</Button>
            {!blocked && shortfall > 0 ? (
              <Button onClick={() => { setOpen(false); navigate('/assinatura') }}>
                <Wallet size={15} /> {t('autopilot.buyCredits')}
              </Button>
            ) : (
              <Button
                onClick={confirm}
                disabled={blocked || starting}
                className="text-white"
                style={{ background: 'linear-gradient(135deg, #7C3AED, #EC4899)' }}
              >
                {starting ? <InlineSpinner size={15} /> : <Sparkles size={15} />}
                {t('autopilot.start')}
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
