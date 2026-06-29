import { NavLink, Link } from 'react-router-dom'
import { ChevronsUpDown, LogOut, Check, Plus } from 'lucide-react'
import { BrandMark } from '@/components/brand/BrandMark'
import { PERSONAL_NAV, NAV_ITEMS, FOOTER_NAV } from './navItems'
import { useLogout } from '@/hooks/useAuth'
import { useWorkspaceMutations } from '@/hooks/useData'
import { Avatar } from '@/components/ui/avatar'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem,
  DropdownMenuLabel, DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu'
import { cn } from '@/lib/utils'

function NavRow({ to, label, icon: Icon, color, onNavigate }) {
  return (
    <NavLink to={to} onClick={onNavigate}>
      {({ isActive }) => (
        <div
          className={cn(
            'group relative flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold transition-all',
            isActive ? 'text-white' : 'text-white/55 hover:text-white hover:bg-white/[0.06]',
          )}
          style={isActive ? { background: 'rgba(255,255,255,0.10)' } : undefined}
        >
          {isActive && <span className="absolute left-0 top-1/2 h-5 w-1 -translate-y-1/2 rounded-r-full" style={{ background: color }} />}
          <span
            className="flex size-7 items-center justify-center rounded-lg transition-colors"
            style={{ background: isActive ? color : 'rgba(255,255,255,0.06)', color: isActive ? '#fff' : color }}
          >
            <Icon size={16} strokeWidth={2.3} />
          </span>
          {label}
        </div>
      )}
    </NavLink>
  )
}

function SectionLabel({ children }) {
  return (
    <p className="px-3 pb-1 pt-2 text-[10px] font-bold uppercase tracking-[0.16em] text-white/30">{children}</p>
  )
}

export default function Sidebar({ me, onNavigate }) {
  const logout = useLogout()
  const { switch: switchWs } = useWorkspaceMutations()
  const workspace = me?.workspace
  const workspaces = me?.workspaces || []
  const user = me?.user

  return (
    <aside className="bg-shell-gradient flex h-full w-[252px] shrink-0 flex-col">
      {/* Brand */}
      <div className="px-4 pb-2 pt-5">
        <Link to="/painel" onClick={onNavigate} className="flex items-center gap-2.5 px-1">
          <BrandMark className="size-9 drop-shadow-md" />
          <span className="font-display text-lg font-extrabold tracking-tight text-white">agencios</span>
        </Link>
      </div>

      {/* Nav */}
      <nav className="flex-1 space-y-0.5 overflow-y-auto px-3 pb-2 no-scrollbar">
        {/* Você — the user's own views, across every team */}
        <SectionLabel>Você</SectionLabel>
        {PERSONAL_NAV.map((item) => <NavRow key={item.to} {...item} onNavigate={onNavigate} />)}

        {/* Team — switcher + workspace-scoped nav, grouped in a frosted "glass" panel
            so these controls read clearly as "this team", distinct from the personal
            items above. */}
        <div className="mt-3 rounded-2xl border border-white/10 bg-white/[0.05] p-2 backdrop-blur-sm">
          <DropdownMenu>
            <DropdownMenuTrigger className="flex w-full items-center gap-2.5 rounded-xl border border-white/10 bg-white/[0.04] px-2.5 py-2 text-left transition hover:bg-white/[0.08]">
              <span className="flex size-8 items-center justify-center rounded-lg bg-brand-gradient text-xs font-black text-white">
                {(workspace?.name || 'A')[0].toUpperCase()}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-bold text-white">{workspace?.name || 'Workspace'}</span>
                <span className="block truncate text-[11px] capitalize text-white/45">Plano {workspace?.plan || 'solo'}</span>
              </span>
              <ChevronsUpDown size={15} className="text-white/40" />
            </DropdownMenuTrigger>
            <DropdownMenuContent align="start" className="w-60">
              <DropdownMenuLabel>Seus workspaces</DropdownMenuLabel>
              {workspaces.map((ws) => (
                <DropdownMenuItem key={ws.id} onSelect={() => ws.id !== workspace?.id && switchWs.mutate(ws.id)}>
                  <span className="flex size-6 items-center justify-center rounded-md bg-brand-soft text-[11px] font-black text-brand">{ws.name[0].toUpperCase()}</span>
                  <span className="flex-1 truncate">{ws.name}</span>
                  {ws.id === workspace?.id && <Check size={15} className="text-brand" />}
                </DropdownMenuItem>
              ))}
              <DropdownMenuSeparator />
              <DropdownMenuItem disabled><Plus size={15} /> Novo workspace</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>

          <div className="mt-1 space-y-0.5">
            <SectionLabel>Operação</SectionLabel>
            {NAV_ITEMS.map((item) => <NavRow key={item.to} {...item} onNavigate={onNavigate} />)}
            <SectionLabel>Conta</SectionLabel>
            {FOOTER_NAV.map((item) => <NavRow key={item.to} {...item} onNavigate={onNavigate} />)}
          </div>
        </div>
      </nav>

      {/* User */}
      <div className="border-t border-white/10 p-3">
        <DropdownMenu>
          <DropdownMenuTrigger className="flex w-full items-center gap-2.5 rounded-xl px-2 py-2 text-left transition hover:bg-white/[0.06]">
            <Avatar name={user?.name || user?.email} src={user?.avatar_url} size={34} />
            <span className="min-w-0 flex-1">
              <span className="block truncate text-sm font-bold text-white">{user?.name || 'Você'}</span>
              <span className="block truncate text-[11px] text-white/45">{user?.email}</span>
            </span>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" side="top" className="w-56">
            <DropdownMenuItem onSelect={() => logout.mutate()} className="text-danger data-[highlighted]:text-danger">
              <LogOut size={15} /> Sair
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </aside>
  )
}
