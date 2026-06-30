import { Folder, Building2, User } from 'lucide-react'
import { AsyncCombobox } from '@/components/ui/async-combobox'
import { projectsApi, clientsApi, workspaceApi } from '@/api'

// ── Reusable entity pickers ──────────────────────────────────────────────
// Thin, pre-wired wrappers over AsyncCombobox so client / project / assignee
// selection is defined ONCE and reused everywhere (filters AND forms). They
// inherit every AsyncCombobox prop: pass `variant="field"` for forms (default
// `pill` for filter bars), `initialOption` to show a label before fetch, etc.

export function ProjectSelect({ placeholder = 'Projeto', listParams, ...props }) {
  return (
    <AsyncCombobox
      placeholder={placeholder}
      icon={Folder}
      queryKey={['projects', 'select']}
      fetchPage={({ q, page }) => projectsApi.list({ q, page, per: 20, ...listParams })}
      mapResponse={(d) => ({ items: d.projects || [], hasMore: d.meta?.has_more })}
      getOption={(p) => ({ value: p.id, label: p.name, color: p.color, description: p.client_name })}
      {...props}
    />
  )
}

export function ClientSelect({ placeholder = 'Cliente', listParams, ...props }) {
  return (
    <AsyncCombobox
      placeholder={placeholder}
      icon={Building2}
      queryKey={['clients', 'select']}
      fetchPage={({ q, page }) => clientsApi.list({ q, page, per: 20, ...listParams })}
      mapResponse={(d) => ({ items: d.clients || [], hasMore: d.meta?.has_more })}
      getOption={(c) => ({ value: c.id, label: c.name, description: c.company, avatar: c.logo_url, avatarName: c.name })}
      {...props}
    />
  )
}

export function AssigneeSelect({ placeholder = 'Responsável', listParams, ...props }) {
  return (
    <AsyncCombobox
      placeholder={placeholder}
      icon={User}
      queryKey={['members', 'select']}
      fetchPage={({ q, page }) => workspaceApi.members({ q, page, per: 20, ...listParams })}
      mapResponse={(d) => ({ items: d.memberships || [], hasMore: d.meta?.has_more })}
      getOption={(m) => ({ value: m.user_id, label: m.name, description: m.email })}
      {...props}
    />
  )
}
