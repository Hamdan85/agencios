import { cn } from '@/lib/utils'
import {
  Select, SelectTrigger, SelectValue, SelectContent, SelectItem,
} from '@/components/ui/select'

const ALL = '__all__'

// A small fixed-list select used in filter bars (status, channel, creative type,
// priority…). Mirrors the design-system Select trigger; `undefined` clears it.
// `fullWidth` stretches it for the stacked mobile filter sheet.
export function OptionSelect({ value, onChange, placeholder, options = [], fullWidth, className }) {
  return (
    <Select value={value || ALL} onValueChange={(v) => onChange(v === ALL ? undefined : v)}>
      <SelectTrigger className={cn('h-9 shrink-0 gap-1.5 rounded-xl text-[13px]', fullWidth ? 'w-full' : 'w-auto min-w-[124px]', className)}>
        <SelectValue placeholder={placeholder} />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={ALL}>{placeholder}</SelectItem>
        {options.map((o) => (
          <SelectItem key={o.value} value={String(o.value)}>
            <span className="inline-flex items-center gap-2">
              {o.color && <span className="size-2.5 rounded-full" style={{ background: o.color }} />}
              {o.icon ? <o.icon size={14} strokeWidth={2.3} style={{ color: o.color }} /> : null}
              {o.label}
            </span>
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}

export default OptionSelect
