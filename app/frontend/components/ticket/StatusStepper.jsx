import { WORKFLOW, STATUS_META } from '@/lib/constants'
import { cn } from '@/lib/utils'
import { Check } from 'lucide-react'

// The graphic centerpiece: a 7-step horizontal funnel progress bar.
// Completed steps fill with their status color + check, the current step
// pulses with a ring, upcoming steps are faint. Clicking a step advances.
export default function StatusStepper({ status, onJump, busy = false }) {
  const currentIndex = Math.max(0, WORKFLOW.indexOf(status))

  return (
    <div className="relative overflow-hidden rounded-2xl border border-border bg-surface p-5 shadow-[0_1px_2px_rgba(24,18,43,0.04),0_8px_24px_-16px_rgba(24,18,43,0.12)]">
      <div className="pointer-events-none absolute -right-10 -top-12 size-40 rounded-full opacity-[0.06]" style={{ background: STATUS_META[status]?.color }} />
      {/* pt/pb give the scaled current node + pulse ring room: overflow-x-auto
          forces overflow-y to clip (CSS spec), so the animation needs padding
          inside the scroll box rather than bleeding past its top edge. */}
      <div className="relative flex items-stretch gap-1 overflow-x-auto no-scrollbar px-1 pb-1 pt-3 sm:gap-2">
        {WORKFLOW.map((key, i) => {
          const m = STATUS_META[key]
          const Icon = m.icon
          const done = i < currentIndex
          const current = i === currentIndex
          const upcoming = i > currentIndex
          const connectorFilled = i <= currentIndex

          return (
            <div key={key} className="flex min-w-[64px] flex-1 flex-col items-center sm:min-w-0">
              {/* connector + node row */}
              <div className="flex w-full items-center">
                <span
                  className={cn('h-1 flex-1 rounded-full transition-colors', i === 0 ? 'opacity-0' : '')}
                  style={{ background: connectorFilled ? m.color : 'var(--ag-connector, #E7E3F0)' }}
                />
                <button
                  type="button"
                  disabled={busy || current}
                  onClick={() => onJump?.(key)}
                  title={m.label}
                  className={cn(
                    'group relative mx-0.5 flex size-10 shrink-0 items-center justify-center rounded-2xl transition-all',
                    !current && !busy && 'hover:scale-110 hover:shadow-md',
                    current && 'scale-110',
                    busy && 'cursor-wait',
                  )}
                  style={{
                    background: done ? m.color : current ? `${m.color}1A` : 'var(--ag-step-bg, #F4F2F9)',
                    color: upcoming ? '#B6B1C9' : done ? '#fff' : m.color,
                    boxShadow: current ? `0 0 0 4px ${m.color}33` : undefined,
                  }}
                >
                  {current && (
                    <span
                      className="absolute inset-0 rounded-2xl"
                      style={{ boxShadow: `0 0 0 3px ${m.color}`, animation: 'ag-pulse-ring 1.8s ease-out infinite' }}
                    />
                  )}
                  {done ? <Check size={18} strokeWidth={3} /> : <Icon size={18} strokeWidth={2.4} />}
                </button>
                <span
                  className={cn('h-1 flex-1 rounded-full transition-colors', i === WORKFLOW.length - 1 ? 'opacity-0' : '')}
                  style={{ background: i < currentIndex ? STATUS_META[WORKFLOW[i + 1]]?.color : 'var(--ag-connector, #E7E3F0)' }}
                />
              </div>
              <span
                className={cn(
                  'mt-2 text-center text-[10.5px] font-bold leading-tight sm:text-[11px]',
                  current ? '' : upcoming ? 'text-ink-faint' : 'text-ink-secondary',
                )}
                style={current ? { color: m.color } : undefined}
              >
                {m.short}
              </span>
            </div>
          )
        })}
      </div>
      <style>{`
        @keyframes ag-pulse-ring {
          0% { opacity: 0.7; transform: scale(1); }
          70% { opacity: 0; transform: scale(1.35); }
          100% { opacity: 0; transform: scale(1.35); }
        }
      `}</style>
    </div>
  )
}
