import * as React from 'react'
import { cva } from 'class-variance-authority'
import { cn } from '@/lib/utils'

const badgeVariants = cva(
  'inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-bold tracking-wide transition-colors',
  {
    variants: {
      variant: {
        default: 'bg-brand text-white',
        soft: 'bg-brand-soft text-brand',
        outline: 'border border-border text-ink-secondary',
        success: 'bg-emerald/12 text-emerald',
        warning: 'bg-amber/15 text-[#B45309]',
        danger: 'bg-danger/12 text-danger',
        muted: 'bg-surface-muted text-ink-muted',
      },
    },
    defaultVariants: { variant: 'default' },
  },
)

function Badge({ className, variant, ...props }) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />
}

// A vivid color-tinted badge from an arbitrary hex (for status/channel/project
// chips). `tint` is the hex-alpha suffix for the wash background.
function ColorBadge({ color, children, className, solid = false, tint = '1A', ...props }) {
  const style = solid
    ? { background: color, color: '#fff' }
    : { background: `${color}${tint}`, color }
  return (
    <span
      className={cn('inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-bold', className)}
      style={style}
      {...props}
    >
      {children}
    </span>
  )
}

export { Badge, ColorBadge, badgeVariants }
