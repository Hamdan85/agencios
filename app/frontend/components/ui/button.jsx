import * as React from 'react'
import { Slot } from '@radix-ui/react-slot'
import { cva } from 'class-variance-authority'
import { cn } from '@/lib/utils'

const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-xl text-sm font-semibold transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand/40 focus-visible:ring-offset-1 disabled:pointer-events-none disabled:opacity-50 active:scale-[0.97] [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0',
  {
    variants: {
      variant: {
        default: 'bg-brand-gradient text-white shadow-[0_8px_20px_-8px_rgba(124,58,237,0.6)] hover:shadow-[0_10px_28px_-8px_rgba(124,58,237,0.7)] hover:brightness-105',
        solid: 'bg-brand text-white hover:bg-brand-deep',
        destructive: 'bg-danger text-white hover:brightness-95 shadow-[0_8px_20px_-8px_rgba(244,63,94,0.5)]',
        outline: 'border border-border bg-surface text-ink hover:border-brand/40 hover:bg-brand-soft',
        secondary: 'bg-surface-muted text-ink-secondary hover:bg-ink-ghost/60 hover:text-ink',
        ghost: 'text-ink-secondary hover:bg-surface-muted hover:text-ink',
        link: 'text-brand underline-offset-4 hover:underline',
        glow: 'bg-ink text-white hover:bg-brand-ink2',
      },
      size: {
        default: 'h-10 px-4 py-2',
        sm: 'h-9 px-3 text-[13px]',
        lg: 'h-12 px-6 text-base',
        icon: 'h-10 w-10',
        'icon-sm': 'h-8 w-8',
      },
    },
    defaultVariants: { variant: 'default', size: 'default' },
  },
)

const Button = React.forwardRef(({ className, variant, size, asChild = false, ...props }, ref) => {
  const Comp = asChild ? Slot : 'button'
  return <Comp className={cn(buttonVariants({ variant, size, className }))} ref={ref} {...props} />
})
Button.displayName = 'Button'

export { Button, buttonVariants }
