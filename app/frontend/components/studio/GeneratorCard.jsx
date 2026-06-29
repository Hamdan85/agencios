import { ArrowUpRight, Sparkles } from 'lucide-react'

// A big, vivid gradient generator card. Click → opens the generation dialog.
export function GeneratorCard({ icon: Icon, title, subtitle, color, onClick }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="group relative flex flex-col overflow-hidden rounded-2xl p-5 text-left text-white shadow-[0_18px_40px_-20px_rgba(24,18,43,0.5)] transition-all hover:-translate-y-1 hover:shadow-[0_28px_60px_-22px_rgba(24,18,43,0.6)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60 focus-visible:ring-offset-2"
      style={{ background: `linear-gradient(135deg, ${color}, ${shade(color)})` }}
    >
      {/* decorative glow */}
      <span className="pointer-events-none absolute -right-8 -top-10 size-36 rounded-full bg-white/20 blur-2xl" />
      <span className="pointer-events-none absolute -bottom-12 -left-6 size-32 rounded-full bg-black/10 blur-2xl" />

      <div className="relative flex items-center justify-between">
        <div className="grid size-12 place-items-center rounded-2xl bg-white/20 backdrop-blur-sm ring-1 ring-white/30">
          <Icon size={24} strokeWidth={2.2} />
        </div>
        <span className="grid size-8 place-items-center rounded-full bg-white/15 transition-transform group-hover:rotate-45 group-hover:bg-white/25">
          <ArrowUpRight size={16} strokeWidth={2.6} />
        </span>
      </div>

      <h3 className="relative mt-4 font-display text-xl font-extrabold tracking-tight">{title}</h3>
      <p className="relative mt-1 text-sm font-medium text-white/85">{subtitle}</p>

      <span className="relative mt-4 inline-flex items-center gap-1.5 text-[12px] font-bold uppercase tracking-wider text-white/90">
        <Sparkles size={13} strokeWidth={2.6} /> Gerar com IA
      </span>
    </button>
  )
}

// Darken a hex color for the gradient's second stop.
function shade(hex) {
  const c = hex.replace('#', '')
  const num = parseInt(c.length === 3 ? c.split('').map((x) => x + x).join('') : c, 16)
  const r = Math.max(0, ((num >> 16) & 255) - 38)
  const g = Math.max(0, ((num >> 8) & 255) - 38)
  const b = Math.max(0, (num & 255) - 38)
  return `#${[r, g, b].map((v) => v.toString(16).padStart(2, '0')).join('')}`
}
