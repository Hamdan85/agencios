import {
  LayoutDashboard, KanbanSquare, CalendarDays, CalendarRange, ListChecks, ListTodo,
  FolderKanban, Users, Sparkles, Video, Receipt, Settings, CreditCard, Megaphone,
} from 'lucide-react'

// The Portuguese route segments are user-facing (browser address bar) by design.

// "Você" — the user's own cross-team views, scoped to the person, not a workspace.
export const PERSONAL_NAV = [
  { to: '/minhas-tarefas', label: 'Minhas tarefas', icon: ListTodo, color: '#F59E0B' },
  { to: '/meu-calendario', label: 'Meu calendário', icon: CalendarRange, color: '#0EA5E9' },
  { to: '/reunioes', label: 'Reuniões', icon: Video, color: '#14B8A6' },
]

// "Operação" — the active workspace's day-to-day, ordered by daily importance:
// the daily cycle first (Painel → Tickets → Tarefas), then structure
// (Clientes → Campanhas → Publicações), then support and money.
export const NAV_ITEMS = [
  { to: '/painel', label: 'Painel', icon: LayoutDashboard, color: '#7C3AED' },
  { to: '/tickets', label: 'Tickets', icon: KanbanSquare, color: '#EC4899' },
  { to: '/tarefas', label: 'Tarefas', icon: ListChecks, color: '#F59E0B' },
  { to: '/calendario', label: 'Calendário', icon: CalendarDays, color: '#0EA5E9' },
  { to: '/clientes', label: 'Clientes', icon: Users, color: '#6366F1' },
  { to: '/campanhas', label: 'Campanhas', icon: FolderKanban, color: '#10B981' },
  { to: '/publicacoes', label: 'Publicações', icon: Megaphone, color: '#0EA5E9' },
  { to: '/estudio', label: 'Estúdio', icon: Sparkles, color: '#F43F5E' },
  { to: '/cobrancas', label: 'Cobranças', icon: Receipt, color: '#F97316' },
]

export const FOOTER_NAV = [
  { to: '/configuracoes', label: 'Configurações', icon: Settings, color: '#8B86A3' },
  { to: '/assinatura', label: 'Assinatura', icon: CreditCard, color: '#8B86A3' },
]
