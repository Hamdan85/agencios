// Display formatters. Backend sends ISO 8601 dates + money in cents — format
// here, always in the ACTIVE language (i18n.language), never a hardcoded locale.
import i18n from '@/i18n'

const locale = () => i18n.language || 'pt-BR'
const t = (key, opts) => i18n.t(key, { ns: 'common', ...opts })

export function dt(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString(locale(), {
    day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
  })
}

export function shortDt(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString(locale(), { day: '2-digit', month: 'short' })
}

export function date(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString(locale(), { day: '2-digit', month: 'long', year: 'numeric' })
}

export function time(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleTimeString(locale(), { hour: '2-digit', minute: '2-digit' })
}

// Money display. The platform's money flows are BRL (Stripe plans, Mercado Pago
// invoices, credit pricing) — only the FORMATTING follows the active language.
export function money(cents, currency = 'BRL') {
  const value = (Number(cents) || 0) / 100
  return value.toLocaleString(locale(), { style: 'currency', currency })
}

// Legacy alias — every existing call site formats BRL cents.
export const brl = money

// Currency input mask: free-typed digits → grouped decimal in the active
// language ("1.234,56" pt-BR / "1,234.56" en). Drives a controlled <Input>;
// pair with centsFromMasked() to read the value back.
export function maskCurrency(value) {
  const digits = String(value ?? '').replace(/\D/g, '')
  if (!digits) return ''
  const cents = parseInt(digits, 10)
  return (cents / 100).toLocaleString(locale(), { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

// Integer cents from a masked currency string ("1.234,56" → 123456).
export function centsFromMasked(value) {
  const digits = String(value ?? '').replace(/\D/g, '')
  return digits ? parseInt(digits, 10) : 0
}

// Raw digits of a masked value ("(11) 99999-9999" → "11999999999"). Use to read
// back the unformatted value for submission/validation.
export function onlyDigits(value) {
  return String(value ?? '').replace(/\D/g, '')
}

// Brazilian phone mask: progressive "(00) 00000-0000" (mobile, 11 digits) and
// "(00) 0000-0000" (landline, 10 digits). Caps at 11 digits.
// The BR-domain masks below (phone/CPF/CNPJ/CEP) are legal/format-specific to
// Brazil — they don't localize; agencies bill Brazilian clients via Mercado Pago
// regardless of the UI language.
export function maskPhone(value) {
  const d = onlyDigits(value).slice(0, 11)
  if (d.length <= 2) return d.replace(/^(\d{0,2})/, '($1')
  if (d.length <= 6) return d.replace(/^(\d{2})(\d{0,4})/, '($1) $2')
  if (d.length <= 10) return d.replace(/^(\d{2})(\d{4})(\d{0,4})/, '($1) $2-$3')
  return d.replace(/^(\d{2})(\d{5})(\d{0,4})/, '($1) $2-$3')
}

// CPF mask: "000.000.000-00". Caps at 11 digits.
export function maskCpf(value) {
  const d = onlyDigits(value).slice(0, 11)
  return d
    .replace(/^(\d{3})(\d)/, '$1.$2')
    .replace(/^(\d{3})\.(\d{3})(\d)/, '$1.$2.$3')
    .replace(/^(\d{3})\.(\d{3})\.(\d{3})(\d)/, '$1.$2.$3-$4')
}

// CNPJ mask: "00.000.000/0000-00". Caps at 14 digits.
export function maskCnpj(value) {
  const d = onlyDigits(value).slice(0, 14)
  return d
    .replace(/^(\d{2})(\d)/, '$1.$2')
    .replace(/^(\d{2})\.(\d{3})(\d)/, '$1.$2.$3')
    .replace(/^(\d{2})\.(\d{3})\.(\d{3})(\d)/, '$1.$2.$3/$4')
    .replace(/^(\d{2})\.(\d{3})\.(\d{3})\/(\d{4})(\d)/, '$1.$2.$3/$4-$5')
}

// CPF/CNPJ auto-detect by digit count: ≤11 digits → CPF, otherwise CNPJ.
export function maskDocument(value) {
  return onlyDigits(value).length <= 11 ? maskCpf(value) : maskCnpj(value)
}

// CEP mask: "00000-000". Caps at 8 digits.
export function maskCep(value) {
  const d = onlyDigits(value).slice(0, 8)
  return d.replace(/^(\d{5})(\d)/, '$1-$2')
}

export function compact(n) {
  return Number(n || 0).toLocaleString(locale(), { notation: 'compact', maximumFractionDigits: 1 })
}

// Plain integer with locale thousands separators ("12.345" pt-BR / "12,345" en).
export function num(n) {
  return Number(n || 0).toLocaleString(locale())
}

// Signed percentage ("+12,5%", "-3%"). Null in → null out (render nothing).
export function pct(n) {
  if (n == null) return null
  const v = Number(n)
  return `${v > 0 ? '+' : ''}${v.toLocaleString(locale(), { maximumFractionDigits: 1 })}%`
}

// Human file size: 0 B, 12 KB, 3,4 MB, 1,1 GB.
export function fileSize(bytes) {
  const b = Number(bytes) || 0
  if (b < 1024) return `${b} B`
  const units = ['KB', 'MB', 'GB', 'TB']
  let value = b / 1024
  let i = 0
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024
    i += 1
  }
  return `${value.toLocaleString(locale(), { maximumFractionDigits: value < 10 ? 1 : 0 })} ${units[i]}`
}

// "agora", "há 5 min", "há 3 h", "ontem", "há 3 dias" — for PAST timestamps
// (created_at). Deadlines use relativeDay below, which speaks in "atraso".
export function timeAgo(iso) {
  if (!iso) return null
  const secs = Math.round((Date.now() - new Date(iso)) / 1000)
  if (secs < 60) return t('time.now')
  const mins = Math.round(secs / 60)
  if (mins < 60) return t('time.minutesAgo', { count: mins })
  const hours = Math.round(mins / 60)
  if (hours < 24) return t('time.hoursAgo', { count: hours })
  const days = Math.round(hours / 24)
  if (days === 1) return t('time.yesterday')
  if (days < 30) return t('time.daysAgo', { count: days })
  return date(iso)
}

// "há 3 dias", "em 2 dias", "hoje"
export function relativeDay(iso) {
  if (!iso) return null
  const diff = Math.round((new Date(iso) - new Date()) / 86400000)
  if (diff === 0) return { text: t('time.today'), tone: 'danger' }
  if (diff === 1) return { text: t('time.tomorrow'), tone: 'warning' }
  if (diff === -1) return { text: t('time.yesterday'), tone: 'muted' }
  if (diff < 0) return { text: t('time.daysLate', { count: Math.abs(diff) }), tone: 'danger' }
  if (diff <= 3) return { text: t('time.inDays', { count: diff }), tone: 'warning' }
  return { text: t('time.inDays', { count: diff }), tone: 'muted' }
}
