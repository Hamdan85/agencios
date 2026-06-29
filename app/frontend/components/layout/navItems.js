import {
  LayoutDashboard, KanbanSquare, CalendarDays, CalendarRange, ListChecks, ListTodo,
  FolderKanban, Users, Sparkles, Video, Receipt, Settings, CreditCard, Rows3,
} from 'lucide-react'

// The Portuguese route segments are user-facing (browser address bar) by design.

// "Você" — the user's own cross-team views, scoped to the person, not a workspace.
export const PERSONAL_NAV = [
  { to: '/minhas-tarefas', label: 'Minhas tarefas', icon: ListTodo, color: '#F59E0B' },
  { to: '/meu-calendario', label: 'Meu calendário', icon: CalendarRange, color: '#0EA5E9' },
]

// "Operação" — the active workspace's day-to-day.
export const NAV_ITEMS = [
  { to: '/painel', label: 'Painel', icon: LayoutDashboard, color: '#7C3AED' },
  { to: '/quadro', label: 'Quadro', icon: KanbanSquare, color: '#EC4899' },
  { to: '/tickets', label: 'Tickets', icon: Rows3, color: '#06B6D4' },
  { to: '/calendario', label: 'Calendário', icon: CalendarDays, color: '#0EA5E9' },
  { to: '/tarefas', label: 'Tarefas', icon: ListChecks, color: '#F59E0B' },
  { to: '/projetos', label: 'Projetos', icon: FolderKanban, color: '#10B981' },
  { to: '/clientes', label: 'Clientes', icon: Users, color: '#6366F1' },
  { to: '/estudio', label: 'Estúdio', icon: Sparkles, color: '#F43F5E' },
  { to: '/reunioes', label: 'Reuniões', icon: Video, color: '#14B8A6' },
  { to: '/cobrancas', label: 'Cobranças', icon: Receipt, color: '#F97316' },
]

export const FOOTER_NAV = [
  { to: '/configuracoes', label: 'Configurações', icon: Settings, color: '#8B86A3' },
  { to: '/assinatura', label: 'Assinatura', icon: CreditCard, color: '#8B86A3' },
]
