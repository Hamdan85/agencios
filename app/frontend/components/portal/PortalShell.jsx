import { useTranslation, Trans } from 'react-i18next'
import { readableOn, tint } from '@/lib/color'

// The branded chrome of the client central: agency header (logo/name/colors) and
// the "feito com ✳ Agencios" signature. Mirrors the main app shell — a fixed
// full-height frame (`h-dvh`, no page scroll): the header + footer stay put and
// only the content band (`main`) scrolls, and only when a view needs it (the
// board scrolls its columns internally; lists/metrics scroll themselves). Each
// child owns its own width/padding/scroll — `main` is a bare flex container so
// board columns can run full-bleed while lists stay centered. `--agency`
// exposes the accent to descendants.
export default function PortalShell({ agency = {}, children, subtitle }) {
  const { t } = useTranslation('portal')
  const accent = agency.primary_color || '#7C3AED'
  const fg = readableOn(accent)

  return (
    <div className="flex h-dvh flex-col overflow-hidden" style={{ background: tint(accent, 5), '--agency': accent }}>
      <header className="z-30 shrink-0 px-5 py-3.5 shadow-sm" style={{ background: accent, color: fg }}>
        <div className="mx-auto flex max-w-6xl items-center gap-3">
          {agency.logo_url
            ? <img src={agency.logo_url} alt={agency.name} className="size-9 rounded-lg bg-white object-cover" />
            : <div className="flex size-9 items-center justify-center rounded-lg bg-white/20 font-bold">{agency.name?.[0] || 'A'}</div>}
          <div className="min-w-0">
            <span className="block truncate font-display text-base font-bold leading-tight">{agency.name}</span>
            {subtitle && <span className="block truncate text-xs opacity-90">{subtitle}</span>}
          </div>
        </div>
      </header>

      <main className="flex min-h-0 flex-1 flex-col overflow-hidden">{children}</main>

      <footer className="shrink-0 py-2 text-center">
        <a href="https://agencios.app" target="_blank" rel="noreferrer" className="text-[11px] font-medium text-ink-faint hover:text-ink-muted">
          <Trans t={t} i18nKey="shell.madeWith" components={{ star: <span style={{ color: '#7C3AED' }} /> }} />
        </a>
      </footer>
    </div>
  )
}
