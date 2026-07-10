import { MoreHorizontal, Archive, ArchiveRestore, Trash2 } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem,
} from '@/components/ui/dropdown-menu'
import { useConfirm } from '@/components/ui/confirm-dialog'

// The "…" actions of the ticket detail surfaces (drawer + full page):
// archive/restore plus a confirmed, final delete. `onDeleted` lets each surface
// leave gracefully (close the drawer / navigate back to the origin).
// `hasScheduledPosts` makes archiving explicit about canceling pending schedules
// (the backend cancels them — an archived ticket must never publish);
// `hasPublishedPosts` makes deleting explicit about losing live-post history.
export default function TicketActionsMenu({
  ticket, mut, onDeleted, hasScheduledPosts = false, hasPublishedPosts = false,
  size = 'icon', variant = 'outline',
}) {
  const { t } = useTranslation('ticket')
  const confirm = useConfirm()
  const busy = mut.archive.isPending || mut.unarchive.isPending || mut.destroy.isPending

  const handleDelete = async () => {
    const ok = await confirm({
      title: t('actionsMenu.deleteTitle'),
      description: hasPublishedPosts
        ? t('actionsMenu.deleteWithLive')
        : t('actionsMenu.deleteDefault'),
      confirmLabel: t('actionsMenu.deleteConfirm'),
      destructive: true,
    })
    if (!ok) return
    mut.destroy.mutate(undefined, { onSuccess: () => onDeleted?.() })
  }

  const handleArchive = async () => {
    if (hasScheduledPosts) {
      const ok = await confirm({
        title: t('actionsMenu.archiveTitle'),
        description: t('actionsMenu.archiveDescription'),
        confirmLabel: t('actionsMenu.archiveConfirm'),
        destructive: true,
      })
      if (!ok) return
    }
    mut.archive.mutate()
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant={variant} size={size} aria-label={t('actionsMenu.aria')} disabled={busy} className="shrink-0">
          <MoreHorizontal size={16} />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="min-w-44">
        {ticket.archived ? (
          <DropdownMenuItem onClick={() => mut.unarchive.mutate()}>
            <ArchiveRestore size={15} /> {t('actions.restore')}
          </DropdownMenuItem>
        ) : (
          <DropdownMenuItem onClick={handleArchive}>
            <Archive size={15} /> {t('actions.archive')}
          </DropdownMenuItem>
        )}
        <DropdownMenuItem onClick={handleDelete} className="text-danger focus:text-danger">
          <Trash2 size={15} /> {t('actions.delete')}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
