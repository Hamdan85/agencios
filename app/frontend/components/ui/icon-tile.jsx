import { cn } from '@/lib/utils'

// The tinted icon square used across page headers, stat cards, dialogs, cards
// and empty states: a soft wash of `color` behind the icon in full `color`.
// `size` picks the tile + icon scale; `tint` is the hex-alpha suffix appended
// to `color` for the wash.
const SIZES = {
  xs: { tile: 'size-8 rounded-lg', icon: 16, stroke: 2.2 },
  sm: { tile: 'size-9 rounded-xl', icon: 18, stroke: 2.2 },
  md: { tile: 'size-12 rounded-2xl', icon: 24, stroke: 2.2 },
  lg: { tile: 'size-16 rounded-2xl', icon: 30, stroke: 2 },
}

export function IconTile({ icon: Icon, color = '#7C3AED', size = 'md', tint = '16', iconSize, strokeWidth, className }) {
  const s = SIZES[size] || SIZES.md
  return (
    <div
      className={cn('flex shrink-0 items-center justify-center', s.tile, className)}
      style={{ background: `${color}${tint}`, color }}
    >
      {Icon && <Icon size={iconSize ?? s.icon} strokeWidth={strokeWidth ?? s.stroke} />}
    </div>
  )
}
