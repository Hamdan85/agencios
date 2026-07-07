import { cn } from '@/lib/utils'

// Uppercase eyebrow micro-label for section/field headings ("DETALHES",
// "MÉTRICAS", …). Override tracking/size/color via className when a surface
// uses a tighter variant.
export function SectionLabel({ as: Tag = 'p', className, children }) {
  return (
    <Tag className={cn('text-[11px] font-bold uppercase tracking-[0.14em] text-ink-muted', className)}>
      {children}
    </Tag>
  )
}
