import * as React from 'react'
import * as TabsPrimitive from '@radix-ui/react-tabs'
import { Dialog, DialogContent, DialogTitle } from './dialog'
import { cn } from '@/lib/utils'

// A WIDE settings dialog with a LEFT vertical icon+text tab rail — for editing an
// entity's sections without walking a linear wizard (jump straight to the section
// you want). Radix Tabs (vertical) drives roving focus / a11y; the rail styling is
// ours. On mobile the DialogContent goes fullscreen and the rail flips to a
// horizontal scroll strip above the panel.
//
// Props:
//   open / onOpenChange   — dialog visibility
//   title                 — dialog title (also the Radix DialogTitle, required for a11y)
//   description           — optional subtitle shown above the panel body
//   icon                  — lucide icon component for the header tile
//   accent                — hex accent for the header tile
//   sections              — [{ key, label, icon }] rail items
//   value / onValueChange — active tab key (controlled)
//   footer                — node rendered in the sticky panel footer (actions)
//   width                 — '2xl' | '3xl' | '4xl' | '5xl'
//   children              — the <SettingsPanel value=…> panels
const WIDTHS = { '2xl': 'sm:max-w-2xl', '3xl': 'sm:max-w-3xl', '4xl': 'sm:max-w-4xl', '5xl': 'sm:max-w-5xl' }

export function SettingsDialog({
  open, onOpenChange, title, description, icon: Icon, accent = '#6366F1',
  sections = [], value, onValueChange, footer, width = '4xl', children,
}) {
  // On mobile the rail is a horizontally SCROLLING strip, and Radix doesn't scroll the
  // active trigger into view. So when the tab changes programmatically (e.g. a failed
  // save jumping back to the invalid section) the target chip can sit off-screen and it
  // looks like the button did nothing. Keep the active chip visible.
  const listRef = React.useRef(null)
  React.useEffect(() => {
    const active = listRef.current?.querySelector('[data-state="active"]')
    active?.scrollIntoView({ block: 'nearest', inline: 'center', behavior: 'smooth' })
  }, [value])

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      {/* DialogContent ships `max-sm:p-5` + `max-sm:overflow-y-auto` for plain dialogs.
          This one manages its own padding and its own single scroll container, so we
          must override BOTH on mobile — and only a `max-sm:` utility can beat a
          `max-sm:` one (tailwind-merge keys them separately, so a bare `p-0` loses).
          Without this the panel pays 20px of padding it doesn't want and gets a
          second, nested scroller. */}
      <DialogContent
        className={cn(
          'gap-0 overflow-hidden p-0 sm:p-0',
          'max-sm:p-0! max-sm:overflow-hidden!',
          WIDTHS[width],
        )}
      >
        <TabsPrimitive.Root
          value={value}
          onValueChange={onValueChange}
          orientation="vertical"
          className="flex min-h-0 flex-col max-sm:h-full sm:h-[min(600px,82vh)] sm:flex-row"
        >
          {/* max-sm:pr-12 keeps the last chip from sliding under the absolute close X. */}
          <TabsPrimitive.List
            ref={listRef}
            className="no-scrollbar flex shrink-0 gap-1 overflow-x-auto border-b border-border bg-surface-muted/40 p-3 max-sm:pr-12 sm:w-60 sm:flex-col sm:overflow-y-auto sm:overflow-x-visible sm:border-b-0 sm:border-r"
          >
            <div className="mb-2 hidden items-center gap-2.5 px-1.5 sm:flex">
              {Icon && (
                <span className="grid size-9 shrink-0 place-items-center rounded-xl" style={{ background: `${accent}16`, color: accent }}>
                  <Icon size={18} strokeWidth={2.2} />
                </span>
              )}
              <DialogTitle className="truncate text-base">{title}</DialogTitle>
            </div>
            {sections.map((s) => (
              <TabsPrimitive.Trigger
                key={s.key}
                value={s.key}
                className={cn(
                  'inline-flex shrink-0 items-center gap-2.5 whitespace-nowrap rounded-lg px-3 py-2 text-sm font-semibold transition-all max-sm:h-11 sm:w-full',
                  'text-ink-muted hover:bg-surface hover:text-ink',
                  'data-[state=active]:bg-surface data-[state=active]:text-ink data-[state=active]:shadow-sm',
                )}
              >
                {s.icon && <s.icon size={16} className="shrink-0" />}
                <span className="truncate">{s.label}</span>
                {/* The unsaved-changes dot: `ml-auto` only works in the vertical rail,
                    so on mobile it rides as a badge on the chip instead of being hidden. */}
                {s.dirty && <span className="size-1.5 shrink-0 rounded-full bg-brand sm:ml-auto" />}
              </TabsPrimitive.Trigger>
            ))}
          </TabsPrimitive.List>

          <div className="flex min-h-0 min-w-0 flex-1 flex-col">
            {/* Mobile has no room for the rail header, so the title lives here instead —
                without it the phone shows a strip of chips and no dialog name at all. */}
            <div className="flex shrink-0 items-center gap-2.5 border-b border-border px-4 pb-3 pt-4 sm:hidden">
              {Icon && (
                <span className="grid size-8 shrink-0 place-items-center rounded-xl" style={{ background: `${accent}16`, color: accent }}>
                  <Icon size={16} strokeWidth={2.2} />
                </span>
              )}
              <DialogTitle className="truncate text-base">{title}</DialogTitle>
            </div>
            {description && (
              <p className="shrink-0 border-b border-border px-6 pb-3 pt-5 text-sm text-ink-muted max-sm:px-4 max-sm:pb-2.5 max-sm:pt-3.5">{description}</p>
            )}
            <div className="min-h-0 flex-1 overflow-y-auto px-6 py-5 max-sm:overscroll-contain max-sm:px-4 max-sm:py-4">{children}</div>
            {footer && (
              // The dialog's own safe-area padding was dropped with `max-sm:p-0!`, so the
              // action bar carries it — it's the element that must clear the home indicator.
              <div className="flex shrink-0 items-center justify-end gap-2 border-t border-border bg-surface px-6 py-3.5 max-sm:px-4 max-sm:pb-[calc(env(safe-area-inset-bottom)+0.875rem)]">{footer}</div>
            )}
          </div>
        </TabsPrimitive.Root>
      </DialogContent>
    </Dialog>
  )
}

export const SettingsPanel = React.forwardRef(({ className, ...props }, ref) => (
  <TabsPrimitive.Content
    ref={ref}
    className={cn('mt-0 focus-visible:outline-none data-[state=inactive]:hidden', className)}
    {...props}
  />
))
SettingsPanel.displayName = 'SettingsPanel'
