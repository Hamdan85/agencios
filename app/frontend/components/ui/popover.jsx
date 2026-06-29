import * as React from 'react'
import * as PopoverPrimitive from '@radix-ui/react-popover'
import { cn } from '@/lib/utils'

const Popover = PopoverPrimitive.Root
const PopoverTrigger = PopoverPrimitive.Trigger
const PopoverAnchor = PopoverPrimitive.Anchor

// Content renders in its own portal (the data-radix-popover-content attribute is
// what the Dialog dismiss-guard looks for, so a popover opened inside a dialog
// closes itself on outside-click instead of closing the whole dialog).
const PopoverContent = React.forwardRef(
  ({ className, align = 'start', sideOffset = 6, ...props }, ref) => (
    <PopoverPrimitive.Portal>
      <PopoverPrimitive.Content
        ref={ref}
        align={align}
        sideOffset={sideOffset}
        data-radix-popover-content=""
        className={cn(
          'z-[9999] w-auto rounded-2xl border border-border bg-surface p-3 text-ink shadow-xl outline-none',
          'data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=open]:zoom-in-95 data-[state=closed]:zoom-out-95',
          className,
        )}
        {...props}
      />
    </PopoverPrimitive.Portal>
  ),
)
PopoverContent.displayName = 'PopoverContent'

export { Popover, PopoverTrigger, PopoverAnchor, PopoverContent }
