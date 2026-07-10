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
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className={cn('gap-0 overflow-hidden p-0 sm:p-0', WIDTHS[width])}>
        <TabsPrimitive.Root
          value={value}
          onValueChange={onValueChange}
          orientation="vertical"
          className="flex min-h-0 flex-col sm:h-[min(600px,82vh)] sm:flex-row"
        >
          <TabsPrimitive.List
            className="no-scrollbar flex shrink-0 gap-1 overflow-x-auto border-b border-border bg-surface-muted/40 p-3 sm:w-60 sm:flex-col sm:overflow-y-auto sm:overflow-x-visible sm:border-b-0 sm:border-r"
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
                  'inline-flex shrink-0 items-center gap-2.5 whitespace-nowrap rounded-lg px-3 py-2 text-sm font-semibold transition-all sm:w-full',
                  'text-ink-muted hover:bg-surface hover:text-ink',
                  'data-[state=active]:bg-surface data-[state=active]:text-ink data-[state=active]:shadow-sm',
                )}
              >
                {s.icon && <s.icon size={16} className="shrink-0" />}
                <span className="truncate">{s.label}</span>
                {s.dirty && <span className="ml-auto hidden size-1.5 rounded-full bg-brand sm:block" />}
              </TabsPrimitive.Trigger>
            ))}
          </TabsPrimitive.List>

          <div className="flex min-h-0 min-w-0 flex-1 flex-col">
            {description && (
              <p className="shrink-0 border-b border-border px-6 pb-3 pt-5 text-sm text-ink-muted">{description}</p>
            )}
            <div className="min-h-0 flex-1 overflow-y-auto px-6 py-5">{children}</div>
            {footer && (
              <div className="flex shrink-0 items-center justify-end gap-2 border-t border-border px-6 py-3.5">{footer}</div>
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
