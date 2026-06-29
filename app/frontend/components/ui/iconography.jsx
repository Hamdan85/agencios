import { statusMeta, channelMeta, creativeMeta, PRIORITY_META } from '@/lib/constants'
import { cn } from '@/lib/utils'

// A vivid status pill with icon + label — the core funnel signifier.
export function StatusPill({ status, size = 'md', withIcon = true, className }) {
  const m = statusMeta(status)
  const Icon = m.icon
  const sm = size === 'sm'
  return (
    <span
      className={cn('inline-flex items-center gap-1.5 rounded-full font-bold', sm ? 'px-2 py-0.5 text-[11px]' : 'px-2.5 py-1 text-xs', className)}
      style={{ background: `${m.color}1A`, color: m.color }}
    >
      {withIcon && <Icon size={sm ? 11 : 13} strokeWidth={2.5} />}
      {m.label}
    </span>
  )
}

// A small color dot for a status.
export function StatusDot({ status, size = 8 }) {
  const m = statusMeta(status)
  return <span className="inline-block rounded-full" style={{ width: size, height: size, background: m.color }} />
}

// The network icons for a ticket's target channels.
export function ChannelIcons({ channels = [], size = 14, max = 6 }) {
  const shown = channels.slice(0, max)
  return (
    <div className="flex items-center gap-1">
      {shown.map((c) => {
        const m = channelMeta(c)
        const Icon = m.icon
        return (
          <span key={c} className="inline-flex items-center justify-center rounded-md" style={{ width: size + 8, height: size + 8, background: `${m.color}18`, color: m.color }} title={m.label}>
            <Icon size={size} strokeWidth={2.2} />
          </span>
        )
      })}
    </div>
  )
}

export function CreativeTypeChip({ type, className }) {
  if (!type) return null
  const m = creativeMeta(type)
  const Icon = m.icon
  return (
    <span className={cn('inline-flex items-center gap-1.5 rounded-lg px-2 py-0.5 text-[11px] font-bold', className)} style={{ background: `${m.color}14`, color: m.color }}>
      <Icon size={12} strokeWidth={2.4} />
      {m.label}
    </span>
  )
}

export function PriorityDot({ priority }) {
  const m = PRIORITY_META[priority] || PRIORITY_META.medium
  return (
    <span className="inline-flex items-center gap-1 text-[11px] font-bold" style={{ color: m.color }}>
      <span className="inline-block size-1.5 rounded-full" style={{ background: m.dot }} />
      {m.label}
    </span>
  )
}
