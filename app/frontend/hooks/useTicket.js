import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { ticketsApi, attachmentsApi } from '@/api'
import { keys } from '@/api/queryKeys'
import { toast } from 'sonner'
import analytics, { EVENTS } from '@/lib/analytics'
import { invalidateTicketSurfaces } from './data/shared'

export function useTicket(id) {
  return useQuery({
    queryKey: keys.ticket(id),
    queryFn: () => ticketsApi.get(id),
    enabled: !!id,
  })
}

export function useTicketMutations(id) {
  const { t } = useTranslation('ticket')
  const qc = useQueryClient()
  const invalidate = () => invalidateTicketSurfaces(qc, { ticketId: id })

  const mk = (fn, okMsg, onDone) =>
    useMutation({
      mutationFn: fn,
      onSuccess: (data, variables) => {
        invalidate()
        if (okMsg) toast.success(okMsg)
        onDone?.(data, variables)
      },
      onError: (err) => toast.error(err.error || t('toasts.genericError')),
    })

  return {
    update: mk((data) => ticketsApi.update(id, data)),
    advance: mk(({ toStatus, position }) => ticketsApi.advance(id, toStatus, position), t('toasts.statusUpdated')),
    publish: mk((payload) => ticketsApi.publish(id, payload), undefined, () => analytics.track(EVENTS.POST_CREATED)),
    summarize: mk(() => ticketsApi.summarize(id)),
    // Fire-and-forget: this only ENQUEUES the rewrite. The success toast + field
    // adoption happen when the ticket channel broadcasts ai_fill_done (see
    // useAiFillStatus) — so no okMsg here, or it would fire before any work runs.
    aiAction: mk((payload) => ticketsApi.aiAction(id, payload), undefined, () => analytics.track(EVENTS.AI_ACTION)),
    generateSubtasks: mk(() => ticketsApi.generateSubtasks(id), t('toasts.checklistGenerated'), () => analytics.track(EVENTS.AI_ACTION)),
    addSubtask: mk((data) => ticketsApi.createSubtask(id, data)),
    addNote: mk((payload) => ticketsApi.createNote(id, payload)),
    generate: mk(
      (payload) => ticketsApi.generateCreative(id, payload),
      t('toasts.generationStarted'),
      (_data, payload) => analytics.track(EVENTS.CREATIVE_GENERATED, { kind: payload?.kind || payload?.creative_type, source: 'ticket' }),
    ),
    removeCreative: mk((creativeId) => ticketsApi.destroyCreative(id, creativeId), t('toasts.creativeRemoved')),
    // Both also affect the Studio gallery's "unassigned" pool — invalidate it too.
    uploadCreative: mk(
      (payload) => ticketsApi.uploadCreative(id, payload),
      t('toasts.creativeUploaded'),
      () => qc.invalidateQueries({ queryKey: ['creatives'] }),
    ),
    attachCreative: mk(
      (creativeId) => ticketsApi.attachCreative(id, creativeId),
      t('toasts.creativeAttached'),
      () => qc.invalidateQueries({ queryKey: ['creatives'] }),
    ),
    // Autopilot ("GO mode"). Estimate is fetched imperatively (mutateAsync) for
    // the confirm dialog; autopilot launches the run after confirmation.
    autopilotEstimate: mk(() => ticketsApi.autopilotEstimate(id)),
    autopilot: mk((payload) => ticketsApi.autopilotStart(id, payload), t('toasts.autopilotStarted')),
    addPost: mk((data) => ticketsApi.createPost(id, data), undefined, () => analytics.track(EVENTS.POST_CREATED)),
    unpublishPost: mk((postId) => ticketsApi.unpublishPost(id, postId), t('toasts.postUnpublished')),
    // Retry a failed publication on its own network — the rest of the bundle is untouched.
    retryPost: mk((postId) => ticketsApi.retryPost(id, postId), t('toasts.postRetrying')),
    // Cancel a scheduled/failed publication (deletes the post before it goes live).
    removePost: mk((postId) => ticketsApi.destroyPost(id, postId), t('toasts.scheduleCanceled')),
    // Ticket lifecycle: archive hides it from the active views; destroy is final.
    archive: mk(() => ticketsApi.archive(id), t('toasts.ticketArchived'), () => qc.invalidateQueries({ queryKey: ['tickets'] })),
    unarchive: mk(() => ticketsApi.unarchive(id), t('toasts.ticketRestored'), () => qc.invalidateQueries({ queryKey: ['tickets'] })),
    destroy: mk(() => ticketsApi.destroy(id), t('toasts.ticketDeleted'), () => {
      qc.invalidateQueries({ queryKey: ['tickets'] })
      qc.invalidateQueries({ queryKey: ['projects'] })
    }),
    uploadAttachments: mk(({ files, meta }) => attachmentsApi.create(id, files, meta), t('toasts.filesUploaded')),
    updateAttachment: mk(({ attachmentId, data }) => attachmentsApi.update(id, attachmentId, data), t('toasts.attachmentUpdated')),
    removeAttachment: mk((attachmentId) => attachmentsApi.destroy(id, attachmentId), t('toasts.attachmentRemoved')),
    invalidate,
  }
}
