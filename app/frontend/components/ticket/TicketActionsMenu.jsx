import { MoreHorizontal, Archive, ArchiveRestore, Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem,
} from '@/components/ui/dropdown-menu'
import { useConfirm } from '@/components/ui/confirm-dialog'

// The "…" actions of the ticket detail surfaces (drawer + full page):
// archive/restore plus a confirmed, final delete. `onDeleted` lets each surface
// leave gracefully (close the drawer / navigate back to the origin).
// `hasScheduledPosts` makes archiving explicit about canceling pending schedules
// (the backend cancels them — an archived ticket must never publish).
export default function TicketActionsMenu({
  ticket, mut, onDeleted, hasScheduledPosts = false, size = 'icon', variant = 'outline',
}) {
  const confirm = useConfirm()
  const busy = mut.archive.isPending || mut.unarchive.isPending || mut.destroy.isPending

  const handleDelete = async () => {
    const ok = await confirm({
      title: 'Excluir ticket?',
      description: 'Isso remove o ticket com suas tarefas, criativos e publicações agendadas. Esta ação não pode ser desfeita.',
      confirmLabel: 'Excluir ticket',
      destructive: true,
    })
    if (!ok) return
    mut.destroy.mutate(undefined, { onSuccess: () => onDeleted?.() })
  }

  const handleArchive = async () => {
    if (hasScheduledPosts) {
      const ok = await confirm({
        title: 'Arquivar ticket?',
        description: 'Este ticket tem publicações agendadas — arquivar cancela esses agendamentos. Você pode restaurar e reagendar depois.',
        confirmLabel: 'Arquivar e cancelar',
        destructive: true,
      })
      if (!ok) return
    }
    mut.archive.mutate()
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant={variant} size={size} aria-label="Mais ações" disabled={busy} className="shrink-0">
          <MoreHorizontal size={16} />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="min-w-44">
        {ticket.archived ? (
          <DropdownMenuItem onClick={() => mut.unarchive.mutate()}>
            <ArchiveRestore size={15} /> Restaurar
          </DropdownMenuItem>
        ) : (
          <DropdownMenuItem onClick={handleArchive}>
            <Archive size={15} /> Arquivar
          </DropdownMenuItem>
        )}
        <DropdownMenuItem onClick={handleDelete} className="text-danger focus:text-danger">
          <Trash2 size={15} /> Excluir
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
