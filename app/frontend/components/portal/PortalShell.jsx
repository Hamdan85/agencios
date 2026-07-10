import { readableOn, tint } from '@/lib/color'

// The branded chrome of the client central: agency header (logo/name/colors) and
// the "feito com ✳ Agencios" signature. Generalized from the approval portal
// shell so the whole central shares one look. `--agency` exposes the accent to
// descendants; the page body scrolls (unlike the no-scroll approval deck). The
// header is sticky so the brand + context stay in view while scrolling; the
// "back to campaigns" affordance lives on the page, not here.
export default function PortalShell({ agency = {}, children, subtitle }) {
  const accent = agency.primary_color || '#7C3AED'
  const fg = readableOn(accent)

  return (
    <div className="flex min-h-dvh flex-col" style={{ background: tint(accent, 5), '--agency': accent }}>
      <header className="sticky top-0 z-30 shrink-0 px-5 py-3.5 shadow-sm" style={{ background: accent, color: fg }}>
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

      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-6 sm:px-6">{children}</main>

      <footer className="shrink-0 py-3 text-center">
        <a href="https://agencios.app" target="_blank" rel="noreferrer" className="text-[11px] font-medium text-ink-faint hover:text-ink-muted">
          feito com <span style={{ color: '#7C3AED' }}>✳</span> Agencios
        </a>
      </footer>
    </div>
  )
}
