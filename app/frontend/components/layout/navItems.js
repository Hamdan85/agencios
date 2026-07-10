import {
  LayoutDashboard, KanbanSquare, CalendarDays, CalendarRange, ListChecks, ListTodo,
  FolderKanban, Users, Sparkles, Video, Receipt, Settings, CreditCard, Megaphone,
} from 'lucide-react'
import i18n from '@/i18n'

// The Portuguese route segments are user-facing (browser address bar) by design.
// Labels resolve through i18n at read time (getter) so they follow the active
// locale without consumers changing how they read `item.label`.

// "Você" — the user's own cross-team views, scoped to the person, not a workspace.
export const PERSONAL_NAV = [
  { to: '/minhas-tarefas', get label() { return i18n.t('layout:nav.myTasks') }, icon: ListTodo, color: '#F59E0B' },
  { to: '/meu-calendario', get label() { return i18n.t('layout:nav.myCalendar') }, icon: CalendarRange, color: '#0EA5E9' },
  { to: '/reunioes', get label() { return i18n.t('layout:nav.meetings') }, icon: Video, color: '#14B8A6' },
]

// "Operação" — the active workspace's day-to-day, ordered by daily importance:
// the daily cycle first (Painel → Tickets → Tarefas), then structure
// (Clientes → Campanhas → Publicações), then support and money.
export const NAV_ITEMS = [
  { to: '/painel', get label() { return i18n.t('layout:nav.dashboard') }, icon: LayoutDashboard, color: '#7C3AED' },
  { to: '/tickets', get label() { return i18n.t('layout:nav.tickets') }, icon: KanbanSquare, color: '#EC4899' },
  { to: '/tarefas', get label() { return i18n.t('layout:nav.tasks') }, icon: ListChecks, color: '#F59E0B' },
  { to: '/calendario', get label() { return i18n.t('layout:nav.calendar') }, icon: CalendarDays, color: '#0EA5E9' },
  { to: '/clientes', get label() { return i18n.t('layout:nav.clients') }, icon: Users, color: '#6366F1' },
  { to: '/campanhas', get label() { return i18n.t('layout:nav.projects') }, icon: FolderKanban, color: '#10B981' },
  { to: '/publicacoes', get label() { return i18n.t('layout:nav.posts') }, icon: Megaphone, color: '#0EA5E9' },
  { to: '/estudio', get label() { return i18n.t('layout:nav.studio') }, icon: Sparkles, color: '#F43F5E' },
  { to: '/cobrancas', get label() { return i18n.t('layout:nav.invoices') }, icon: Receipt, color: '#F97316' },
]

export const FOOTER_NAV = [
  { to: '/configuracoes', get label() { return i18n.t('layout:nav.settings') }, icon: Settings, color: '#8B86A3' },
  { to: '/assinatura', get label() { return i18n.t('layout:nav.subscription') }, icon: CreditCard, color: '#8B86A3' },
]
