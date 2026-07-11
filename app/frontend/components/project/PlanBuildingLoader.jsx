import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Sparkles } from 'lucide-react'
import { cn } from '@/lib/utils'

// The phases the strategist moves through — cycled as ambient copy so the wait
// feels like watching the plan take shape rather than a dead spinner.
const PHASE_KEYS = [
  'readingBrandContext',
  'designingCadence',
  'choosingHooks',
  'writingBriefs',
  'schedulingPosts',
  'estimatingTasks',
  'finishingTouches',
]

// A mesmerizing "the agent is building your plan" animation: a drifting aurora,
// a breathing spark medallion ringed by pulsing halos and orbiting particles,
// and cycling status copy. Pure CSS/GPU transforms — no deps, seek-safe.
export function PlanBuildingLoader({ className }) {
  const { t } = useTranslation('projects')
  const [phase, setPhase] = useState(0)
  useEffect(() => {
    const id = setInterval(() => setPhase((p) => (p + 1) % PHASE_KEYS.length), 2100)
    return () => clearInterval(id)
  }, [])

  return (
    <div
      className={cn(
        'relative grid min-h-[240px] place-items-center overflow-hidden rounded-2xl border border-brand/15',
        'bg-[radial-gradient(120%_120%_at_50%_-10%,rgba(6,182,212,0.10),transparent_60%)]',
        className,
      )}
    >
      <style>{loaderKeyframes}</style>

      {/* Drifting aurora blobs */}
      <span aria-hidden className="pointer-events-none absolute -left-16 -top-16 size-56 rounded-full bg-brand/25 blur-3xl [animation:pb-drift-a_9s_ease-in-out_infinite]" />
      <span aria-hidden className="pointer-events-none absolute -bottom-20 -right-10 size-56 rounded-full bg-indigo/20 blur-3xl [animation:pb-drift-b_11s_ease-in-out_infinite]" />
      <span aria-hidden className="pointer-events-none absolute bottom-0 left-1/3 size-40 rounded-full bg-emerald/15 blur-3xl [animation:pb-drift-a_13s_ease-in-out_infinite_reverse]" />

      <div className="relative flex flex-col items-center gap-6 px-6 py-8">
        {/* Medallion */}
        <div className="relative grid size-24 place-items-center">
          {/* Pulsing halos */}
          <span aria-hidden className="absolute inset-0 rounded-full border border-brand/30 [animation:pb-ripple_2.8s_ease-out_infinite]" />
          <span aria-hidden className="absolute inset-0 rounded-full border border-brand/30 [animation:pb-ripple_2.8s_ease-out_infinite] [animation-delay:1.4s]" />

          {/* Slowly rotating conic sweep */}
          <span
            aria-hidden
            className="absolute inset-1 rounded-full opacity-70 [animation:pb-spin_5.5s_linear_infinite]"
            style={{ background: 'conic-gradient(from 0deg, transparent 0deg, rgba(6,182,212,0.55) 90deg, transparent 200deg)', mask: 'radial-gradient(farthest-side, transparent calc(100% - 3px), #000 calc(100% - 3px))', WebkitMask: 'radial-gradient(farthest-side, transparent calc(100% - 3px), #000 calc(100% - 3px))' }}
          />

          {/* Orbiting particles */}
          <span aria-hidden className="absolute inset-0 [animation:pb-spin_4s_linear_infinite]">
            <span className="absolute left-1/2 top-0 size-2 -translate-x-1/2 rounded-full bg-brand shadow-[0_0_10px_2px_rgba(6,182,212,0.6)]" />
          </span>
          <span aria-hidden className="absolute inset-0 [animation:pb-spin_6s_linear_infinite_reverse]">
            <span className="absolute bottom-0 left-1/2 size-1.5 -translate-x-1/2 rounded-full bg-indigo shadow-[0_0_8px_2px_rgba(99,102,241,0.55)]" />
          </span>

          {/* Core */}
          <span className="relative grid size-14 place-items-center rounded-full bg-surface shadow-[0_8px_30px_-8px_rgba(6,182,212,0.6)] ring-1 ring-brand/20 [animation:pb-breathe_2.6s_ease-in-out_infinite]">
            <Sparkles size={24} strokeWidth={2.2} className="text-brand [animation:pb-twinkle_2.6s_ease-in-out_infinite]" />
          </span>
        </div>

        {/* Cycling phase copy */}
        <div className="flex min-h-[20px] items-center">
          <span key={phase} className="text-sm font-semibold text-ink-secondary [animation:pb-fade_2.1s_ease-in-out]">
            {t(`loader.${PHASE_KEYS[phase]}`)}
          </span>
        </div>

        {/* Indeterminate shimmer bar */}
        <div className="h-1.5 w-56 max-w-full overflow-hidden rounded-full bg-surface-muted">
          <span className="block h-full w-1/3 rounded-full bg-gradient-to-r from-transparent via-brand to-transparent [animation:pb-slide_1.5s_ease-in-out_infinite]" />
        </div>
      </div>
    </div>
  )
}

const loaderKeyframes = `
@keyframes pb-drift-a { 0%,100% { transform: translate(0,0) scale(1); } 50% { transform: translate(28px,20px) scale(1.15); } }
@keyframes pb-drift-b { 0%,100% { transform: translate(0,0) scale(1.05); } 50% { transform: translate(-24px,-18px) scale(0.9); } }
@keyframes pb-spin { to { transform: rotate(360deg); } }
@keyframes pb-breathe { 0%,100% { transform: scale(1); } 50% { transform: scale(1.09); } }
@keyframes pb-twinkle { 0%,100% { opacity: 0.75; transform: rotate(0deg); } 50% { opacity: 1; transform: rotate(12deg); } }
@keyframes pb-ripple { 0% { transform: scale(0.7); opacity: 0.9; } 100% { transform: scale(1.5); opacity: 0; } }
@keyframes pb-fade { 0% { opacity: 0; transform: translateY(6px); } 20%,80% { opacity: 1; transform: translateY(0); } 100% { opacity: 0.85; } }
@keyframes pb-slide { 0% { transform: translateX(-120%); } 100% { transform: translateX(320%); } }
@media (prefers-reduced-motion: reduce) {
  [class*="pb-"] { animation: none !important; }
}
`

export default PlanBuildingLoader
