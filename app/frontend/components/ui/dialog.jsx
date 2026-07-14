import * as React from 'react'
import * as DialogPrimitive from '@radix-ui/react-dialog'
import { X } from 'lucide-react'
import { cn } from '@/lib/utils'
import { guardLightboxInteractOutside } from '@/components/ui/lightbox-guard'

const Dialog = DialogPrimitive.Root
const DialogTrigger = DialogPrimitive.Trigger
const DialogPortal = DialogPrimitive.Portal
const DialogClose = DialogPrimitive.Close

const DialogOverlay = React.forwardRef(({ className, ...props }, ref) => (
  <DialogPrimitive.Overlay
    ref={ref}
    className={cn(
      'fixed inset-0 z-50 bg-brand-ink/40 backdrop-blur-sm data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0',
      className,
    )}
    {...props}
  />
))
DialogOverlay.displayName = 'DialogOverlay'

const DialogContent = React.forwardRef(({ className, children, onInteractOutside, ...props }, ref) => (
  <DialogPortal>
    <DialogOverlay />
    <DialogPrimitive.Content
      ref={ref}
      className={cn(
        // focus:outline-none — Radix focuses the content on open; without this the
        // browser draws a stray focus ring around the whole dialog.
        'fixed left-[50%] top-[50%] z-50 grid w-full max-w-lg translate-x-[-50%] translate-y-[-50%] gap-4 rounded-2xl border border-border bg-surface p-6 shadow-2xl duration-200 focus:outline-none',
        // Mobile: take over the full screen so forms have room and never get
        // clipped by a narrow viewport. Desktop (sm+) keeps the centered card
        // above untouched, including any caller-provided max-w-*.
        'max-sm:inset-0 max-sm:h-full max-sm:translate-x-0 max-sm:translate-y-0 max-sm:max-w-none! max-sm:max-h-none! max-sm:rounded-none max-sm:border-0 max-sm:p-5 max-sm:pb-[calc(env(safe-area-inset-bottom)+1.25rem)] max-sm:overflow-y-auto',
        'data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95',
        // Radix Select is unconditionally modal (no `modal` prop in this version):
        // while open it sets `pointer-events: none` on <body> and on this content,
        // so a click inside the dialog falls through to <html> and the dialog reads
        // it as an outside click and closes. Forcing the content to stay
        // interactive keeps inside-clicks inside — only the select closes.
        '!pointer-events-auto',
        className,
      )}
      // A press inside the lightbox (stacked above this dialog — scenes editor,
      // studio) must close only the lightbox — see lightbox-guard.js.
      onInteractOutside={guardLightboxInteractOutside(onInteractOutside)}
      {...props}
    >
      {children}
      {/* max-sm:p-2.5 → a 44px touch target on phones (24px on desktop is fine with a
          cursor). z-10 + a surface backdrop keeps it legible when it sits over a
          scrolling tab rail (SettingsDialog on mobile). */}
      <DialogPrimitive.Close className="absolute right-4 top-4 rounded-lg p-1 text-ink-muted opacity-70 transition hover:bg-surface-muted hover:opacity-100 focus:outline-none max-sm:z-10 max-sm:bg-surface/80 max-sm:p-2.5 max-sm:backdrop-blur-sm">
        <X className="size-4" />
      </DialogPrimitive.Close>
    </DialogPrimitive.Content>
  </DialogPortal>
))
DialogContent.displayName = 'DialogContent'

const DialogHeader = ({ className, ...props }) => (
  <div className={cn('flex flex-col gap-1.5', className)} {...props} />
)
const DialogTitle = React.forwardRef(({ className, ...props }, ref) => (
  <DialogPrimitive.Title ref={ref} className={cn('font-display text-xl font-bold tracking-tight text-ink', className)} {...props} />
))
DialogTitle.displayName = 'DialogTitle'
const DialogDescription = React.forwardRef(({ className, ...props }, ref) => (
  <DialogPrimitive.Description ref={ref} className={cn('text-sm text-ink-muted', className)} {...props} />
))
DialogDescription.displayName = 'DialogDescription'
const DialogFooter = ({ className, ...props }) => (
  <div className={cn('flex flex-col-reverse gap-2 sm:flex-row sm:justify-end', className)} {...props} />
)

export {
  Dialog, DialogTrigger, DialogContent, DialogHeader, DialogFooter,
  DialogTitle, DialogDescription, DialogClose, DialogPortal, DialogOverlay,
}
