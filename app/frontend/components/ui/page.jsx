import { cn } from '@/lib/utils'

// The standard page shell — the ONE place the outer width + padding live.
//
//   default → centered, max-w-7xl, with comfortable side "breathing room"
//   wide    → uses the full available width (Board / Calendar — maximize columns,
//             the side gutters there waste space and hurt the experience)
//
// Every routed page renders its content inside a <Page>. The app shell
// (Layout) is full-bleed, so Page owns the horizontal rhythm — flip `wide` to
// drop the max-width and gutters for column-dense screens.
export function Page({ wide = false, className, children }) {
  return (
    <div
      className={cn(
        'flex w-full flex-1 flex-col pt-7 pb-[calc(env(safe-area-inset-bottom)+4rem)] sm:py-9',
        wide ? 'px-4 sm:px-6' : 'mx-auto max-w-7xl px-5 sm:px-8',
        className,
      )}
    >
      {children}
    </div>
  )
}

export default Page
