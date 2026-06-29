import * as React from 'react'
import { cn } from '@/lib/utils'

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

const Textarea = React.forwardRef(({ className, ...props }, ref) => (
  <textarea
    ref={ref}
    className={cn(
      'flex min-h-20 w-full rounded-xl border border-border bg-surface-muted px-3.5 py-2.5 text-sm text-ink placeholder:text-ink-faint transition-colors',
      'focus:bg-surface focus:outline-none focus:ring-2 focus:ring-brand/20 focus:border-brand',
      'disabled:cursor-not-allowed disabled:opacity-50 resize-y',
      className,
    )}
    {...props}
  />
))
Textarea.displayName = 'Textarea'

export { Input, Textarea }
