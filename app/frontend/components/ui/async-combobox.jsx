import { useEffect, useRef, useState } from 'react'
import { useInfiniteQuery } from '@tanstack/react-query'
import { Check, ChevronDown, Search, X, Loader2 } from 'lucide-react'
import { Popover, PopoverTrigger, PopoverContent } from '@/components/ui/popover'
import { Spinner } from '@/components/ui/feedback'
import { cn } from '@/lib/utils'

function useDebounced(value, delay = 250) {
  const [v, setV] = useState(value)
  useEffect(() => {
    const t = setTimeout(() => setV(value), delay)
    return () => clearTimeout(t)
  }, [value, delay])
  return v
}

// A single-select combobox backed by a paginated + searchable endpoint.
// Type to search (debounced); scroll to load more pages (IntersectionObserver).
// The selected option's label is remembered locally so it keeps showing on the
// trigger even after the result set changes (e.g. a new search).
//
//   fetchPage:   ({ q, page }) => Promise(response)
//   mapResponse: (response) => ({ items, hasMore })
//   getOption:   (item) => ({ value, label, description?, color?, icon? })
//
// Two looks via `variant`:
//   'pill'  — a compact filter chip (default; used in filter bars)
//   'field' — a full-width form field matching the Select trigger
//
// For edit forms where a value is already set, pass `initialOption` so the
// label shows immediately without waiting for a fetch.
export function AsyncCombobox({
  value,
  onChange,
  placeholder = 'Selecionar',
  icon: TriggerIcon,
  queryKey,
  fetchPage,
  mapResponse,
  getOption,
  className,
  align = 'start',
  width,
  variant = 'pill',
  initialOption = null,
  clearable,
  disabled = false,
  id,
  emptyMessage = 'Nada encontrado',
}) {
  const isField = variant === 'field'
  const canClear = clearable ?? !isField

  const [open, setOpen] = useState(false)
  const [search, setSearch] = useState('')
  const [selected, setSelected] = useState(initialOption)
  const debounced = useDebounced(search, 250)

  // Keep the displayed label in sync with the controlled value: adopt an
  // externally-provided initialOption (edit forms) and drop a stale label when
  // the value is cleared from outside. Callers often build `initialOption`
  // inline (new object each render), so depend on its primitives and bail when
  // unchanged — otherwise setState would re-fire every render.
  const initialValue = initialOption?.value
  const initialLabel = initialOption?.label
  useEffect(() => {
    if (value == null || value === '') { setSelected(null); return }
    if (initialOption && String(initialValue) === String(value)) {
      setSelected((prev) => (prev && prev.value === initialValue && prev.label === initialLabel ? prev : initialOption))
    }
  }, [initialValue, initialLabel, value]) // eslint-disable-line react-hooks/exhaustive-deps

  const query = useInfiniteQuery({
    queryKey: [...queryKey, debounced],
    queryFn: ({ pageParam = 1 }) => fetchPage({ q: debounced, page: pageParam }),
    initialPageParam: 1,
    getNextPageParam: (lastPage, pages) => (mapResponse(lastPage).hasMore ? pages.length + 1 : undefined),
    enabled: open,
    staleTime: 30_000,
  })

  const options = (query.data?.pages || []).flatMap((p) => (mapResponse(p).items || []).map(getOption))

  // If the active value shows up in the loaded options, adopt its label (covers
  // the case where no initialOption was provided). Guarded so it can't loop.
  useEffect(() => {
    if (!value || (selected && String(selected.value) === String(value))) return
    const match = options.find((o) => String(o.value) === String(value))
    if (match) setSelected(match)
  }, [options.length, value]) // eslint-disable-line react-hooks/exhaustive-deps

  // Infinite scroll: fetch the next page when the sentinel scrolls into view.
  const sentinelRef = useRef(null)
  const { hasNextPage, isFetchingNextPage, fetchNextPage } = query
  useEffect(() => {
    const el = sentinelRef.current
    if (!el || !open) return
    const io = new IntersectionObserver(
      (entries) => { if (entries[0].isIntersecting && hasNextPage && !isFetchingNextPage) fetchNextPage() },
      { rootMargin: '120px' },
    )
    io.observe(el)
    return () => io.disconnect()
  }, [open, hasNextPage, isFetchingNextPage, fetchNextPage, options.length])

  const pick = (opt) => {
    setSelected(opt)
    onChange(String(opt.value), opt)
    setOpen(false)
    setSearch('')
  }

  const clear = (e) => {
    e?.preventDefault()
    e?.stopPropagation()
    setSelected(null)
    onChange(undefined, undefined)
  }

  const activeLabel = value ? (selected?.label || '…') : null

  const clearChip = canClear && value ? (
    <span
      role="button"
      tabIndex={-1}
      aria-label="Limpar"
      onPointerDown={(e) => e.stopPropagation()}
      onClick={clear}
      className="shrink-0 rounded-md p-0.5 text-ink-muted transition hover:bg-black/5 hover:text-ink"
    >
      <X size={14} />
    </span>
  ) : null

  const trigger = isField ? (
    <button
      id={id}
      type="button"
      disabled={disabled}
      className={cn(
        'flex h-10 w-full items-center gap-2 rounded-xl border bg-surface-muted px-3.5 text-sm transition-colors',
        'focus:outline-none focus:ring-2 focus:ring-brand/20 disabled:cursor-not-allowed disabled:opacity-50',
        open ? 'border-brand ring-2 ring-brand/20' : 'border-border',
      )}
    >
      {TriggerIcon && <TriggerIcon size={15} strokeWidth={2.2} className="shrink-0 text-ink-muted" />}
      {selected?.color && value && <span className="size-2.5 shrink-0 rounded-full" style={{ background: selected.color }} />}
      <span className={cn('flex-1 truncate text-left', activeLabel ? 'text-ink' : 'text-ink-faint')}>
        {activeLabel || placeholder}
      </span>
      {clearChip}
      <ChevronDown size={16} className="shrink-0 text-ink-muted" />
    </button>
  ) : (
    <button
      type="button"
      disabled={disabled}
      className={cn(
        'flex h-9 items-center gap-1.5 rounded-xl border px-3 text-[13px] font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-brand/30 disabled:opacity-50',
        value
          ? 'border-brand/40 bg-brand-soft text-brand pr-7'
          : 'border-border bg-surface-muted text-ink-secondary hover:border-brand/40',
      )}
    >
      {TriggerIcon && <TriggerIcon size={14} strokeWidth={2.3} className="shrink-0 opacity-80" />}
      <span className="max-w-[150px] truncate">{activeLabel || placeholder}</span>
      {!value && <ChevronDown size={14} className="shrink-0 opacity-50" />}
    </button>
  )

  return (
    <div className={cn('relative', isField ? 'w-full' : 'shrink-0', className)}>
      <Popover open={open} onOpenChange={(o) => { setOpen(o); if (!o) setSearch('') }}>
        <PopoverTrigger asChild>{trigger}</PopoverTrigger>
        <PopoverContent
          align={align}
          className={cn('p-0', isField ? 'w-(--radix-popover-trigger-width)' : (width || 'w-64'))}
        >
          <div className="flex items-center gap-2 border-b border-border px-3 py-2">
            <Search size={14} className="shrink-0 text-ink-faint" />
            <input
              autoFocus
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Buscar…"
              className="w-full bg-transparent text-sm text-ink outline-none placeholder:text-ink-faint"
            />
            {query.isFetching && !isFetchingNextPage && <Loader2 size={14} className="shrink-0 animate-spin text-ink-faint" />}
          </div>

          <div className="scrollbar-subtle max-h-64 overflow-y-auto p-1">
            {options.length === 0 && !query.isFetching && (
              <p className="px-3 py-6 text-center text-[13px] text-ink-faint">{emptyMessage}</p>
            )}
            {options.map((o) => {
              const active = String(o.value) === String(value)
              return (
                <button
                  key={o.value}
                  type="button"
                  onClick={() => pick(o)}
                  className={cn(
                    'flex w-full items-center gap-2 rounded-lg px-2.5 py-2 text-left text-sm transition-colors hover:bg-brand-soft',
                    active && 'bg-brand-soft',
                  )}
                >
                  {o.color && <span className="size-2.5 shrink-0 rounded-full" style={{ background: o.color }} />}
                  {o.icon && <o.icon size={14} strokeWidth={2.3} style={{ color: o.color }} className="shrink-0" />}
                  <span className="min-w-0 flex-1 truncate text-ink">
                    {o.label}
                    {o.description ? <span className="text-ink-faint"> · {o.description}</span> : null}
                  </span>
                  {active && <Check size={15} className="shrink-0 text-brand" />}
                </button>
              )
            })}
            <div ref={sentinelRef} aria-hidden />
            {isFetchingNextPage && <div className="flex justify-center py-2"><Spinner size={16} /></div>}
          </div>
        </PopoverContent>
      </Popover>

      {!isField && value ? (
        <button
          type="button"
          aria-label="Remover filtro"
          onClick={clear}
          className="absolute right-1.5 top-1/2 -translate-y-1/2 rounded-md p-0.5 text-brand/70 transition hover:bg-brand/10 hover:text-brand"
        >
          <X size={13} />
        </button>
      ) : null}
    </div>
  )
}

export default AsyncCombobox
