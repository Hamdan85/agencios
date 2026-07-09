import { useState } from 'react'
import { X } from 'lucide-react'
import { cn } from '@/lib/utils'

// A chips / tags input. Each entry becomes a removable badge; type and press
// Enter or comma to add, Backspace on an empty field removes the last chip.
// Value is an array of strings; `prefix` (e.g. '#') is shown on each chip but
// never stored. Pasting a comma/newline-separated list adds them all. `max`
// caps how many chips can be added (the field hides once the cap is reached).
export function ChipsInput({ value, onChange, placeholder, prefix = '', max = Infinity, className }) {
  const chips = Array.isArray(value) ? value : []
  const [text, setText] = useState('')
  const atMax = chips.length >= max

  const stripPrefix = (s) => (prefix ? s.replace(new RegExp(`^${prefix}+`), '') : s)
  const clean = (raw) => raw.split(/[,\n]/).map((s) => stripPrefix(s.trim()).trim()).filter(Boolean)

  const add = (raw) => {
    const parts = clean(raw)
    if (!parts.length) { setText(''); return }
    const next = [...chips]
    parts.forEach((p) => {
      if (next.length < max && !next.some((c) => c.toLowerCase() === p.toLowerCase())) next.push(p)
    })
    onChange(next)
    setText('')
  }

  const removeAt = (i) => onChange(chips.filter((_, idx) => idx !== i))

  const onKeyDown = (e) => {
    if (e.key === 'Enter' || e.key === ',') { e.preventDefault(); add(text) }
    else if (e.key === 'Backspace' && !text && chips.length) { e.preventDefault(); removeAt(chips.length - 1) }
  }

  return (
    <div
      className={cn(
        'flex min-h-10 flex-wrap items-center gap-1.5 rounded-xl border border-border bg-surface-muted px-2 py-1.5 transition-colors',
        'focus-within:border-brand focus-within:bg-surface focus-within:ring-2 focus-within:ring-brand/20',
        className,
      )}
      onClick={(e) => { if (e.currentTarget === e.target) e.currentTarget.querySelector('input')?.focus() }}
    >
      {chips.map((chip, i) => (
        <span
          key={`${chip}-${i}`}
          className="inline-flex items-center gap-1 rounded-lg bg-brand/12 py-1 pl-2 pr-1 text-[13px] font-semibold text-brand"
        >
          <span className="max-w-[12rem] truncate">{prefix}{chip}</span>
          <button
            type="button"
            aria-label={`Remover ${chip}`}
            onClick={() => removeAt(i)}
            className="grid size-4 place-items-center rounded text-brand/70 transition hover:bg-brand/20 hover:text-brand"
          >
            <X size={12} strokeWidth={2.5} />
          </button>
        </span>
      ))}
      {!atMax && (
        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={onKeyDown}
          onBlur={() => add(text)}
          placeholder={chips.length ? '' : placeholder}
          className="min-w-[6rem] flex-1 border-0 bg-transparent px-1 py-0.5 text-sm text-ink shadow-none outline-none placeholder:text-ink-faint focus:border-0 focus:outline-none focus:ring-0"
        />
      )}
    </div>
  )
}

export default ChipsInput
