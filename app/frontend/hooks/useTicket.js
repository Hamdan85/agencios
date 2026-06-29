import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { ticketsApi, attachmentsApi } from '@/api'
import { keys } from '@/api/queryKeys'
import { toast } from 'sonner'
import analytics, { EVENTS } from '@/lib/analytics'

export function useTicket(id) {
  return useQuery({
    queryKey: keys.ticket(id),
    queryFn: () => ticketsApi.get(id),
    enabled: !!id,
  })
}

export function useTicketMutations(id) {
  const qc = useQueryClient()
  const invalidate = () => {
    qc.invalidateQueries({ queryKey: keys.ticket(id) })
    qc.invalidateQueries({ queryKey: ['board'] })
  }

  const mk = (fn, okMsg, onDone) =>
    useMutation({
      mutationFn: fn,
      onSuccess: (data, variables) => {
        invalidate()
        if (okMsg) toast.success(okMsg)
        onDone?.(data, variables)
      },
      onError: (err) => toast.error(err.error || 'Algo deu errado.'),
    })

  return {
    update: mk((data) => ticketsApi.update(id, data)),
    advance: mk(({ toStatus, position }) => ticketsApi.advance(id, toStatus, position), 'Status atualizado!'),
    summarize: mk(() => ticketsApi.summarize(id)),
    aiAction: mk(() => ticketsApi.aiAction(id), 'IA gerou novidades ✨', () => analytics.track(EVENTS.AI_ACTION)),
    addSubtask: mk((data) => ticketsApi.createSubtask(id, data)),
    addNote: mk((payload) => ticketsApi.createNote(id, payload)),
    generate: mk(
      (payload) => ticketsApi.generateCreative(id, payload),
      'Geração iniciada!',
      (_data, payload) => analytics.track(EVENTS.CREATIVE_GENERATED, { kind: payload?.kind || payload?.creative_type, source: 'ticket' }),
    ),
    addPost: mk((data) => ticketsApi.createPost(id, data), undefined, () => analytics.track(EVENTS.POST_CREATED)),
    uploadAttachments: mk(({ files, meta }) => attachmentsApi.create(id, files, meta), 'Arquivo(s) enviado(s)!'),
    updateAttachment: mk(({ attachmentId, data }) => attachmentsApi.update(id, attachmentId, data), 'Arquivo atualizado!'),
    removeAttachment: mk((attachmentId) => attachmentsApi.destroy(id, attachmentId), 'Arquivo removido.'),
    invalidate,
  }
}
