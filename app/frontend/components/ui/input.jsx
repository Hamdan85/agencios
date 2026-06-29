import * as React from 'react'
import { cn } from '@/lib/utils'

// Tiptap is heavy — only pull it in when a field actually opts into `rich` mode.
const RichTextEditor = React.lazy(() => import('@/components/ui/rich-text'))

const Input = React.forwardRef(({ className, type, ...props }, ref) => (
  <input
    type={type}
    ref={ref}
    className={cn(
      'flex h-10 w-full rounded-xl border border-border bg-surface-muted px-3.5 py-2 text-sm text-ink placeholder:text-ink-faint transition-colors',
      'focus:bg-surface focus:outline-none focus:ring-2 focus:ring-brand/20 focus:border-brand',
      'disabled:cursor-not-allowed disabled:opacity-50',
      className,
    )}
    {...props}
  />
))
Input.displayName = 'Input'

// Merges a forwarded ref with a local one so we can both expose the node and
// measure it for auto-growing.
function useMergedRef(forwarded) {
  const local = React.useRef(null)
  const set = React.useCallback((node) => {
    local.current = node
    if (typeof forwarded === 'function') forwarded(node)
    else if (forwarded) forwarded.current = node
  }, [forwarded])
  return [local, set]
}

// The single multiline text component used everywhere. Defaults to an
// auto-growing plain textarea (no jumpy native resize handle — it grows with
// content up to `maxRows`, then scrolls). Pass `rich` to swap in the Tiptap
// rich-text editor while keeping the same value/onChange(event) contract, so any
// existing `onChange={(e) => set(e.target.value)}` call site works unchanged.
const Textarea = React.forwardRef(function Textarea(
  { className, rich = false, rows = 3, maxRows = 18, value, onChange, onBlur, placeholder, disabled, style, ...props },
  ref,
) {
  // Rich mode: delegate to the editor, adapting its onChange(html) into a
  // synthetic event so plain-text call sites keep working.
  if (rich) {
    return (
      <React.Suspense fallback={<div className="min-h-24 animate-pulse rounded-xl border border-border bg-surface-muted" />}>
        <RichTextEditor
          value={value || ''}
          onChange={(html) => onChange?.({ target: { value: html } })}
          onBlur={() => onBlur?.({ target: { value: value || '' } })}
          placeholder={placeholder}
          disabled={disabled}
          className={className}
          minHeight={`${Math.max(rows, 3) * 1.6}rem`}
        />
      </React.Suspense>
    )
  }

  const [localRef, setRef] = useMergedRef(ref)

  // Grow to fit content (capped at maxRows), otherwise scroll.
  const resize = React.useCallback(() => {
    const el = localRef.current
    if (!el) return
    el.style.height = 'auto'
    const cs = window.getComputedStyle(el)
    const line = parseFloat(cs.lineHeight) || 20
    const pad =
      parseFloat(cs.paddingTop) + parseFloat(cs.paddingBottom) +
      parseFloat(cs.borderTopWidth) + parseFloat(cs.borderBottomWidth)
    const max = line * maxRows + pad
    el.style.height = `${Math.min(el.scrollHeight, max)}px`
    el.style.overflowY = el.scrollHeight > max ? 'auto' : 'hidden'
  }, [localRef, maxRows])

  // Re-measure on value changes (covers controlled updates + external resets).
  React.useLayoutEffect(() => { resize() }, [value, resize])

  return (
    <textarea
      ref={setRef}
      rows={rows}
      value={value}
      placeholder={placeholder}
      disabled={disabled}
      style={style}
      onChange={(e) => { onChange?.(e); resize() }}
      onBlur={onBlur}
      className={cn(
        'block w-full resize-none rounded-xl border border-border bg-surface-muted px-3.5 py-2.5 text-sm text-ink placeholder:text-ink-faint transition-colors',
        'focus:bg-surface focus:outline-none focus:ring-2 focus:ring-brand/20 focus:border-brand',
        'disabled:cursor-not-allowed disabled:opacity-50',
        className,
      )}
      {...props}
    />
  )
})

export { Input, Textarea }
