import * as React from 'react'
import { cn, initials } from '@/lib/utils'

// Deterministic vivid color from a string (name) — graphic, never grey.
const PALETTE = ['#7C3AED', '#EC4899', '#0EA5E9', '#10B981', '#F59E0B', '#6366F1', '#F43F5E', '#14B8A6']
function colorFor(seed = '') {
  let h = 0
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) % PALETTE.length
  return PALETTE[Math.abs(h)]
}

export function Avatar({ name, src, size = 36, className, ring = false }) {
  const color = colorFor(name || '?')
  return (
    <div
      className={cn('inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full font-bold text-white select-none', ring && 'ring-2 ring-white', className)}
      style={{ width: size, height: size, background: src ? undefined : `linear-gradient(135deg, ${color}, ${color}cc)`, fontSize: size * 0.4 }}
      title={name}
    >
      {src ? <img src={src} alt={name} className="size-full object-cover" /> : initials(name)}
    </div>
  )
}

export function AvatarStack({ people = [], max = 4, size = 28 }) {
  const shown = people.slice(0, max)
  const extra = people.length - shown.length
  return (
    <div className="flex items-center">
      {shown.map((p, i) => (
        <div key={p.id ?? i} style={{ marginLeft: i === 0 ? 0 : -8 }}>
          <Avatar name={p.name} src={p.avatar_url} size={size} ring />
        </div>
      ))}
      {extra > 0 && (
        <div
          className="inline-flex items-center justify-center rounded-full bg-surface-muted font-bold text-ink-muted ring-2 ring-white"
          style={{ width: size, height: size, marginLeft: -8, fontSize: size * 0.36 }}
        >
          +{extra}
        </div>
      )}
    </div>
  )
}
