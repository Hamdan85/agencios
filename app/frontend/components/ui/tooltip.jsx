import * as React from 'react'
import * as TooltipPrimitive from '@radix-ui/react-tooltip'
import { cn } from '@/lib/utils'

// Thin wrapper over Radix Tooltip. Each <Tooltip> carries its own Provider so
// callers can drop one in anywhere without wiring a top-level provider.
const TooltipProvider = TooltipPrimitive.Provider
const TooltipRoot = TooltipPrimitive.Root
const TooltipTrigger = TooltipPrimitive.Trigger

const TooltipContent = React.forwardRef(({ className, sideOffset = 6, ...props }, ref) => (
  <TooltipPrimitive.Portal>
    <TooltipPrimitive.Content
      ref={ref}
      sideOffset={sideOffset}
      className={cn(
        'z-50 max-w-[15rem] rounded-lg bg-brand-ink px-2.5 py-1.5 text-xs font-medium leading-snug text-surface shadow-lg',
        'data-[state=delayed-open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=delayed-open]:fade-in-0 data-[state=delayed-open]:zoom-in-95',
        className,
      )}
      {...props}
    />
  </TooltipPrimitive.Portal>
))
TooltipContent.displayName = 'TooltipContent'

// Self-contained tooltip: wraps Root in a Provider so a bare <Tooltip> works.
function Tooltip({ delayDuration = 200, children, ...props }) {
  return (
    <TooltipProvider delayDuration={delayDuration}>
      <TooltipRoot {...props}>{children}</TooltipRoot>
    </TooltipProvider>
  )
}

export { Tooltip, TooltipTrigger, TooltipContent, TooltipProvider }
