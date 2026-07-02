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
    publish: mk((payload) => ticketsApi.publish(id, payload), undefined, () => analytics.track(EVENTS.POST_CREATED)),
    summarize: mk(() => ticketsApi.summarize(id)),
    // Fire-and-forget: this only ENQUEUES the rewrite. The success toast + field
    // adoption happen when the ticket channel broadcasts ai_fill_done (see
    // useAiFillStatus) — so no okMsg here, or it would fire before any work runs.
    aiAction: mk((payload) => ticketsApi.aiAction(id, payload), undefined, () => analytics.track(EVENTS.AI_ACTION)),
    generateSubtasks: mk(() => ticketsApi.generateSubtasks(id), 'Checklist gerada com IA ✨', () => analytics.track(EVENTS.AI_ACTION)),
    addSubtask: mk((data) => ticketsApi.createSubtask(id, data)),
    addNote: mk((payload) => ticketsApi.createNote(id, payload)),
    generate: mk(
      (payload) => ticketsApi.generateCreative(id, payload),
      'Geração iniciada!',
      (_data, payload) => analytics.track(EVENTS.CREATIVE_GENERATED, { kind: payload?.kind || payload?.creative_type, source: 'ticket' }),
    ),
    removeCreative: mk((creativeId) => ticketsApi.destroyCreative(id, creativeId), 'Criativo removido.'),
    // Both also affect the Studio gallery's "unassigned" pool — invalidate it too.
    uploadCreative: mk(
      (payload) => ticketsApi.uploadCreative(id, payload),
      'Criativo enviado!',
      () => qc.invalidateQueries({ queryKey: ['creatives'] }),
    ),
    attachCreative: mk(
      (creativeId) => ticketsApi.attachCreative(id, creativeId),
      'Criativo adicionado ao ticket!',
      () => qc.invalidateQueries({ queryKey: ['creatives'] }),
    ),
    // Autopilot ("GO mode"). Estimate is fetched imperatively (mutateAsync) for
    // the confirm dialog; autopilot launches the run after confirmation.
    autopilotEstimate: mk(() => ticketsApi.autopilotEstimate(id)),
    autopilot: mk((payload) => ticketsApi.autopilotStart(id, payload), 'Piloto automático iniciado 🚀'),
    addPost: mk((data) => ticketsApi.createPost(id, data), undefined, () => analytics.track(EVENTS.POST_CREATED)),
    unpublishPost: mk((postId) => ticketsApi.unpublishPost(id, postId), 'Post despublicado.'),
    uploadAttachments: mk(({ files, meta }) => attachmentsApi.create(id, files, meta), 'Arquivo(s) enviado(s)!'),
    updateAttachment: mk(({ attachmentId, data }) => attachmentsApi.update(id, attachmentId, data), 'Arquivo atualizado!'),
    removeAttachment: mk((attachmentId) => attachmentsApi.destroy(id, attachmentId), 'Arquivo removido.'),
    invalidate,
  }
}
