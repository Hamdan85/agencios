import * as React from 'react'
import * as DialogPrimitive from '@radix-ui/react-dialog'
import { cn } from '@/lib/utils'

// A right-side drawer built on Radix Dialog. Slide animations live in theme.css
// (.ag-sheet-overlay / .ag-sheet-panel), driven by the data-state attribute.
const Sheet = DialogPrimitive.Root
const SheetTrigger = DialogPrimitive.Trigger
const SheetClose = DialogPrimitive.Close
const SheetPortal = DialogPrimitive.Portal

const SheetOverlay = React.forwardRef(({ className, ...props }, ref) => (
  <DialogPrimitive.Overlay
    ref={ref}
    className={cn('ag-sheet-overlay fixed inset-0 z-50 bg-brand-ink/40 backdrop-blur-sm', className)}
    {...props}
  />
))
SheetOverlay.displayName = 'SheetOverlay'

// Per-side positioning + slide animation. `right` is the full-height drawer
// (ticket detail); `bottom` is the mobile bottom sheet (filters).
const SHEET_SIDES = {
  right: 'ag-sheet-panel inset-y-0 right-0 h-full w-full max-w-xl border-l bg-canvas shadow-[-24px_0_60px_-24px_rgba(17,10,36,0.45)]',
  bottom: 'ag-sheet-panel-bottom inset-x-0 bottom-0 max-h-[88dvh] w-full rounded-t-3xl border-t bg-surface shadow-[0_-24px_60px_-24px_rgba(17,10,36,0.45)]',
}

// `overlay={false}` drops the dimming backdrop so a non-modal drawer (e.g. the
// strategy planner) leaves the page behind visible + interactive.
const SheetContent = React.forwardRef(({ className, children, side = 'right', overlay = true, ...props }, ref) => (
  <SheetPortal>
    {overlay && <SheetOverlay />}
    <DialogPrimitive.Content
      ref={ref}
      className={cn(
        'fixed z-50 flex flex-col border-border',
        SHEET_SIDES[side] || SHEET_SIDES.right,
        // Same Radix-Select pointer-events guard the dialog uses: keep the panel
        // interactive so clicks inside a nested Select don't read as outside-clicks.
        '!pointer-events-auto',
        className,
      )}
      {...props}
    >
      {children}
    </DialogPrimitive.Content>
  </SheetPortal>
))
SheetContent.displayName = 'SheetContent'

const SheetTitle = React.forwardRef(({ className, ...props }, ref) => (
  <DialogPrimitive.Title ref={ref} className={cn('font-display font-bold tracking-tight text-ink', className)} {...props} />
))
SheetTitle.displayName = 'SheetTitle'

const SheetDescription = React.forwardRef(({ className, ...props }, ref) => (
  <DialogPrimitive.Description ref={ref} className={cn('text-sm text-ink-muted', className)} {...props} />
))
SheetDescription.displayName = 'SheetDescription'

export {
  Sheet, SheetTrigger, SheetClose, SheetPortal, SheetOverlay, SheetContent, SheetTitle, SheetDescription,
}
