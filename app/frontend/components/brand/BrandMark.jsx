import { cn } from '@/lib/utils'

// The agencios brand mark (gradient squircle "a" + spark). Served from the
// public SVG so it's cached and crisp at any size. Size via `className`
// (defaults to size-9); pairs with the "agencios" wordmark.
export function BrandMark({ className, alt = 'agencios' }) {
  return <img src="/icon.svg" alt={alt} className={cn('block size-9 select-none', className)} draggable={false} />
}

export default BrandMark
