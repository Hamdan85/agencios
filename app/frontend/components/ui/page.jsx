import { cn } from '@/lib/utils'

// The two horizontal rhythms every screen picks between:
//   base → centered, max-w-7xl, comfortable side "breathing room" (list pages)
//   wide → full available width, small gutters (Board / Calendar — column-dense
//          screens where generous gutters waste space)
const GUTTER = {
  base: 'mx-auto w-full max-w-7xl px-5 sm:px-8',
  wide: 'px-4 sm:px-6',
}

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
//
// For screens that switch layouts under a stable header (the tickets hub:
// Quadro ⇄ Lista), compose the split shell below instead —
// <PageShell><PageTitle/><PageContent/></PageShell> — so the title band stays
// put while only the content band changes width/padding.
export function Page({ wide = false, flush = false, className, children }) {
  return (
    <div
      className={cn(
        'flex w-full flex-1 flex-col',
        flush ? 'pt-7 sm:pt-9' : 'pt-7 pb-[calc(env(safe-area-inset-bottom)+4rem)] sm:py-9',
        wide ? GUTTER.wide : GUTTER.base,
        className,
      )}
    >
      {children}
    </div>
  )
}

// ── Split shell: a fixed title band + a variable content band ──────────
// Bare full-height frame that owns no horizontal rhythm of its own — the
// title and content bands inside own theirs. Use when the content region
// changes shape (width / padding / scroll) under a header that must not move.
export function PageShell({ className, children }) {
  return (
    <div className={cn('flex min-h-0 w-full flex-1 flex-col', className)}>
      {children}
    </div>
  )
}

// The title band — sticky to the top of the scroll area, always visible, with
// ONE constant gutter so it never shifts when the content band below changes
// width. Everything up to (and including) the view tabs lives here.
export function PageTitle({ wide = false, className, children }) {
  return (
    <div
      className={cn(
        'sticky top-0 z-20 shrink-0 bg-canvas/85 pt-7 backdrop-blur sm:pt-9',
        wide ? GUTTER.wide : GUTTER.base,
        className,
      )}
    >
      {children}
    </div>
  )
}

// The content band — owns the width/padding variant (and, for list-like pages,
// its own vertical scroll). Switching a page's layout moves only this band, so
// wrap it with a `key` + `animate-rise` to cross-fade the change.
//
//   wide   → full-width gutters (board / calendar)
//   flush  → no safe-area bottom clearance (board fills to the bottom of main)
//   scroll → this band scrolls itself (list view); omit when the page's own
//            children manage scrolling (the board columns scroll internally)
//
// When `scroll` is on, the overflow lives on a full-bleed outer element so the
// scrollbar sits at the screen edge, while the gutter / max-width apply to an
// inner container that expands to fill it. `className` (animation, extra
// padding) rides the inner container — the visible content.
export function PageContent({ wide = false, flush = false, scroll = false, className, children }) {
  const inner = cn(
    'flex w-full flex-1 flex-col',
    flush ? 'pb-2' : 'pb-[calc(env(safe-area-inset-bottom)+4rem)]',
    wide ? GUTTER.wide : GUTTER.base,
    className,
  )

  if (scroll) {
    return (
      <div className="scrollbar-subtle flex min-h-0 w-full flex-1 flex-col overflow-y-auto">
        <div className={inner}>{children}</div>
      </div>
    )
  }

  return <div className={cn('min-h-0', inner)}>{children}</div>
}

export default Page
