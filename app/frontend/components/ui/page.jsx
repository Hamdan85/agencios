import { cn } from '@/lib/utils'

// The standard page shell — the ONE place the outer width + padding live.
//
//   default → centered, max-w-7xl, with comfortable side "breathing room"
//   wide    → uses the full available width, small side gutters only (Board /
//             Calendar — maximize columns, generous gutters there waste space)
//   flush   → drops the huge safe-area bottom clearance (Board) — the board
//             fills to the bottom of `main` itself and doesn't need clearance
//             for a fixed bottom banner the way a normally-scrolled page does.
//             Horizontal gutter is independent of this — still driven by `wide`.
//
// Every routed page renders its content inside a <Page>. The app shell
// (Layout) is full-bleed, so Page owns the horizontal rhythm — flip `wide` to
// drop the max-width and gutters for column-dense screens.
export function Page({ wide = false, flush = false, className, children }) {
  return (
    <div
      className={cn(
        'flex w-full flex-1 flex-col',
        flush ? 'pt-7 sm:pt-9' : 'pt-7 pb-[calc(env(safe-area-inset-bottom)+4rem)] sm:py-9',
        wide ? 'px-4 sm:px-6' : 'mx-auto max-w-7xl px-5 sm:px-8',
        className,
      )}
    >
      {children}
    </div>
  )
}

export default Page
