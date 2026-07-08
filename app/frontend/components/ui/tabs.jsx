import * as React from 'react'
import * as TabsPrimitive from '@radix-ui/react-tabs'
import { cn } from '@/lib/utils'

// Tab state is carried in the URL PATH (a Portuguese route segment), never a
// query string — see the `/configuracoes/:tab`, `/conta/:tab`, `/publicacoes/...`
// pattern. Pages derive the active tab from `useParams`/`useLocation` and drive
// this controlled root with `value`/`onValueChange` that `navigate(...)` the path.
const Tabs = TabsPrimitive.Root

const TabsList = React.forwardRef(({ className, ...props }, ref) => (
  <TabsPrimitive.List
    ref={ref}
    className={cn('no-scrollbar flex items-center gap-1 overflow-x-auto rounded-xl bg-surface-muted p-1 sm:inline-flex sm:overflow-visible', className)}
    {...props}
  />
))
TabsList.displayName = 'TabsList'

const TabsTrigger = React.forwardRef(({ className, ...props }, ref) => (
  <TabsPrimitive.Trigger
    ref={ref}
    className={cn(
      'inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-lg px-3.5 py-1.5 text-sm font-semibold text-ink-muted transition-all',
      'data-[state=active]:bg-surface data-[state=active]:text-ink data-[state=active]:shadow-sm hover:text-ink',
      className,
    )}
    {...props}
  />
))
TabsTrigger.displayName = 'TabsTrigger'

const TabsContent = React.forwardRef(({ className, ...props }, ref) => (
  <TabsPrimitive.Content ref={ref} className={cn('focus-visible:outline-none', className)} {...props} />
))
TabsContent.displayName = 'TabsContent'

export { Tabs, TabsList, TabsTrigger, TabsContent }
