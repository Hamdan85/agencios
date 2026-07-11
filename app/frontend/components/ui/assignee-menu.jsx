import { useTranslation } from 'react-i18next'
import { Check, UserPlus } from 'lucide-react'
import { Avatar } from '@/components/ui/avatar'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu'
import { cn } from '@/lib/utils'

// Canonical inline assignee picker (tickets, subtasks, …): an avatar trigger
// that opens a member list with current-selection checkmarks. `members` are
// workspace memberships (flat shape: { id, user_id, name, avatar_url }); the
// picked value is the *user* id — never the membership id. `value` is the
// currently-selected user id; `onSelect(userId | null)` fires on pick.
export function AssigneeMenu({
  members = [], value = null, name = null, avatarUrl = null,
  onSelect, disabled = false, size = 26, align = 'end',
}) {
  const { t } = useTranslation('ui')
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          type="button"
          style={{ width: size, height: size }}
          className={cn(
            'flex shrink-0 items-center justify-center rounded-full outline-none transition focus:ring-2 focus:ring-brand/40',
            name
              ? 'hover:opacity-80'
              : 'border border-dashed border-ink-faint/60 text-ink-faint hover:border-brand hover:bg-brand/5 hover:text-brand',
          )}
          aria-label={name ? t('assignee.labeled', { name }) : t('assignee.assign')}
          title={name || t('assignee.assign')}
        >
          {name ? <Avatar name={name} src={avatarUrl} size={size} /> : <UserPlus size={Math.round(size * 0.52)} />}
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align={align} className="max-h-72 min-w-48 overflow-y-auto">
        <DropdownMenuLabel>{t('assignee.assignTo')}</DropdownMenuLabel>
        <DropdownMenuItem onClick={() => onSelect?.(null)} disabled={disabled}>
          <span className="text-ink-muted">{t('assignee.unassigned')}</span>
          {value == null && <Check size={14} className="ml-auto !text-brand" />}
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        {members.map((m) => {
          const userId = m.user_id ?? m.id
          return (
            <DropdownMenuItem key={m.id} onClick={() => onSelect?.(userId)} disabled={disabled}>
              <Avatar name={m.name} src={m.avatar_url} size={20} />
              <span className="truncate">{m.name}</span>
              {value === userId && <Check size={14} className="ml-auto !text-brand" />}
            </DropdownMenuItem>
          )
        })}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

export default AssigneeMenu
