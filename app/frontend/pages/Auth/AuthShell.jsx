import { Link } from 'react-router-dom'
import { Sparkles, KanbanSquare, CalendarDays, Wand2 } from 'lucide-react'
import { BrandMark } from '@/components/brand/BrandMark'

const HIGHLIGHTS = [
  { icon: KanbanSquare, color: '#EC4899', text: 'Funil de produção de conteúdo em um quadro vivo' },
  { icon: Wand2, color: '#7C3AED', text: 'Geração de criativos com IA — carrosséis, vídeos, imagens' },
  { icon: CalendarDays, color: '#0EA5E9', text: 'Calendário unificado de posts e reuniões' },
]

export default function AuthShell({ title, subtitle, children, footer }) {
  return (
    <div className="flex min-h-screen">
      {/* Left — brand panel */}
      <div className="bg-shell-gradient relative hidden w-[46%] flex-col justify-between overflow-hidden p-12 lg:flex">
        <div className="absolute inset-0 bg-aurora opacity-80" />
        <div className="relative">
          <Link to="/" className="flex items-center gap-2.5">
            <BrandMark className="size-10 drop-shadow-md" />
            <span className="font-display text-xl font-extrabold text-white">agencios</span>
          </Link>
        </div>
        <div className="relative">
          <span className="inline-flex items-center gap-1.5 rounded-full bg-white/10 px-3 py-1 text-xs font-bold text-white/80">
            <Sparkles size={13} /> O SO da sua agência
          </span>
          <h2 className="mt-4 font-display text-4xl font-extrabold leading-tight text-white">
            Clientes, projetos e conteúdo viral — <span className="text-gradient-brand">num só lugar.</span>
          </h2>
          <div className="mt-8 space-y-4">
            {HIGHLIGHTS.map((h) => (
              <div key={h.text} className="flex items-center gap-3">
                <span className="flex size-9 items-center justify-center rounded-xl" style={{ background: `${h.color}28`, color: h.color }}>
                  <h.icon size={18} strokeWidth={2.3} />
                </span>
                <span className="text-sm font-medium text-white/80">{h.text}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="relative text-xs text-white/40">© {new Date().getFullYear()} agencios</div>
      </div>

      {/* Right — form */}
      <div className="flex flex-1 items-center justify-center bg-canvas px-6 py-12">
        <div className="w-full max-w-sm animate-rise">
          <div className="mb-8 lg:hidden">
            <BrandMark className="size-11" />
          </div>
          <h1 className="font-display text-3xl font-extrabold tracking-tight text-ink">{title}</h1>
          <p className="mt-1.5 text-sm text-ink-muted">{subtitle}</p>
          <div className="mt-8">{children}</div>
          {footer && <div className="mt-6 text-center text-sm text-ink-muted">{footer}</div>}
        </div>
      </div>
    </div>
  )
}
