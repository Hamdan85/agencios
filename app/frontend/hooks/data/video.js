import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import { studioApi, videoScenesApi } from '@/api'
import { keys } from '@/api/queryKeys'
import analytics, { EVENTS } from '@/lib/analytics'
import { onErr } from './shared'

// Video opens as a chat INTERVIEW: no immediate generation — the editor's chat
// gathers context and decides when to build. Returns { creative } to open the
// editor on.
export function useStartVideo() {
  const { t } = useTranslation('studio')
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ params }) => studioApi.startVideo(params),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: keys.studio() })
      qc.invalidateQueries({ queryKey: ['creatives'] })
      analytics.track(EVENTS.CREATIVE_GENERATED, { kind: 'video', source: 'studio', phase: 'interview' })
    },
    onError: onErr(t('videoEditor.openError')),
  })
}

// ── Video scenes (per-scene edit / re-render) ─────────────────
// Returns the full payload ({ scenes, messages }) so the editor can render the
// timeline AND the chat history from one query.
export function useVideoScenes(creativeId, { enabled = true } = {}) {
  const qc = useQueryClient()
  return useQuery({
    queryKey: ['video-scenes', creativeId],
    queryFn: () => videoScenesApi.list(creativeId),
    enabled: enabled && !!creativeId,
    // While any scene is still rendering, poll so the preview/timeline update
    // live (no reload). Stops once every scene is terminal (ready/failed).
    // Paused while a chat turn is in flight so a poll can't clobber the
    // optimistic user bubble with a not-yet-persisted server history.
    refetchInterval: (query) => {
      if (qc.isMutating({ mutationKey: ['video-chat', creativeId] })) return false
      const scenes = query.state.data?.scenes || []
      // Covers the storyboard-planning phase too (creative generating, 0 scenes).
      const busy = query.state.data?.creative?.status === 'generating' ||
        scenes.some((s) => ['rendering', 'fresh', 'stale'].includes(s.render_state))
      return busy ? 4000 : false
    },
  })
}

export function useEditScene(creativeId) {
  const { t } = useTranslation('studio')
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, data }) => videoScenesApi.update(id, data),
    onSuccess: (_data, variables) => {
      qc.invalidateQueries({ queryKey: ['video-scenes', creativeId] })
      qc.invalidateQueries({ queryKey: ['creatives'] })
      qc.invalidateQueries({ queryKey: ['tickets'] })
      if (variables?.data?.prompt) qc.invalidateQueries({ queryKey: ['credits'] }) // a prompt change re-renders (charged)
      toast.success(variables?.data?.prompt ? t('videoEditor.sceneRedoing') : t('videoEditor.sceneUpdated'))
    },
    onError: onErr(t('videoEditor.sceneEditError')),
  })
}

// Approve the draft: re-render the whole storyboard with the final model.
export function useFinalizeVideo(creativeId) {
  const { t } = useTranslation('studio')
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => videoScenesApi.finalize(creativeId),
    onSuccess: (data) => {
      qc.setQueryData(['video-scenes', creativeId], (prev) => ({
        ...(prev || {}),
        creative: data.creative ?? prev?.creative,
        scenes: data.scenes ?? prev?.scenes,
      }))
      qc.invalidateQueries({ queryKey: ['creatives'] })
      qc.invalidateQueries({ queryKey: ['credits'] }) // the upgrade spent credits
      toast.success(t('videoEditor.finalizeStarted'))
    },
    onError: onErr(t('videoEditor.finalizeError')),
  })
}

// Conversational video editor: send a message; the agent replies and may
// re-render one/some/all scenes. The response carries the fresh scenes + the
// full message history, which we write straight into the scenes query cache.
export function useVideoChat(creativeId) {
  const { t } = useTranslation('studio')
  const qc = useQueryClient()
  return useMutation({
    mutationKey: ['video-chat', creativeId],
    mutationFn: ({ message, referenceUrls = [], referenceDescriptions = [], annotations = [] }) =>
      videoScenesApi.chat(creativeId, {
        message, reference_image_urls: referenceUrls, reference_descriptions: referenceDescriptions, annotations,
      }),
    // Optimistic: the user's message lands in the transcript IMMEDIATELY (the
    // typing dots then show while the agent thinks); the server response later
    // replaces the whole history, so no reconciliation is needed on success.
    // Pinned scene annotations are rendered the same way the server stores them.
    onMutate: ({ message, referenceUrls = [], annotations = [] }) => {
      const prev = qc.getQueryData(['video-scenes', creativeId])
      const notes = annotations.map((a) => t('videoEditor.sceneAnnotation', { scene: a.scene, note: a.note })).join('\n')
      const content = annotations.length ? [message, t('videoEditor.notesByScene', { notes })].filter(Boolean).join('\n\n') : message
      qc.setQueryData(['video-scenes', creativeId], (cur) => ({
        ...(cur || {}),
        // Show the attached references as thumbnails right away (server echoes them back).
        messages: [...(cur?.messages || []), { role: 'user', content, images: referenceUrls }],
      }))
      return { prev }
    },
    onError: (err, _msg, ctx) => {
      if (ctx?.prev) qc.setQueryData(['video-scenes', creativeId], ctx.prev)
      onErr(t('videoEditor.chatError'))(err)
    },
    onSuccess: (data) => {
      qc.setQueryData(['video-scenes', creativeId], (prev) => ({
        ...(prev || {}),
        creative: data.creative ?? prev?.creative,
        scenes: data.scenes ?? prev?.scenes,
        messages: data.messages ?? prev?.messages,
      }))
      qc.invalidateQueries({ queryKey: ['creatives'] })
      qc.invalidateQueries({ queryKey: ['tickets'] })
      // A re-render spent credits — refresh the wallet counter + the ledger now
      // (the debit already happened). The COST is shown per-bubble (the server
      // stamps `credits` on the assistant message), so nothing else is needed here.
      if (data.credits_spent > 0) qc.invalidateQueries({ queryKey: ['credits'] })
    },
  })
}

// ── Video assets tab (characters / scenarios / music) ─────────
// The video's created assets, listed for the Assets tab. Only fetched when the
// tab is open (enabled), and reused across regenerations.
export function useVideoAssets(creativeId, { enabled = true } = {}) {
  return useQuery({
    queryKey: ['video-assets', creativeId],
    queryFn: () => videoScenesApi.assets(creativeId),
    enabled: enabled && !!creativeId,
  })
}

// Regenerate ONE element from a prompt. Characters/scenarios spend an image credit
// (and don't re-render the video — the new image is used on the next render);
// music is a free re-search + re-mix. The response carries the fresh element list.
export function useRegenerateAsset(creativeId) {
  const { t } = useTranslation('studio')
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ type, prompt, ref_url }) => videoScenesApi.regenerateAsset(creativeId, { type, prompt, ref_url }),
    onSuccess: (data, variables) => {
      if (data.assets) qc.setQueryData(['video-assets', creativeId], { assets: data.assets })
      // A music change re-mixes the composed file → refresh the scenes/preview.
      if (variables?.type === 'music') qc.invalidateQueries({ queryKey: ['video-scenes', creativeId] })
      else qc.invalidateQueries({ queryKey: ['credits'] }) // an image generation was charged
      toast.success(variables?.type === 'music' ? t('videoEditor.musicUpdated') : t('videoEditor.assetRegenerated'))
    },
    onError: onErr(t('videoEditor.assetRegenerateError')),
  })
}

// Reusable library elements to add to a video (brand assets + other videos' refs).
export function useAssetLibrary(creativeId, { enabled = true } = {}) {
  return useQuery({
    queryKey: ['video-asset-library', creativeId],
    queryFn: () => videoScenesApi.assetLibrary(creativeId),
    enabled: enabled && !!creativeId,
  })
}

// Add an element (uploaded URL or a library asset) under a role — free, no
// re-render (used on the next render). Response carries the fresh element list.
export function useAddAsset(creativeId) {
  const { t } = useTranslation('studio')
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ url, role, description }) => videoScenesApi.addAsset(creativeId, { url, role, description }),
    onSuccess: (data) => {
      if (data.assets) qc.setQueryData(['video-assets', creativeId], { assets: data.assets })
      toast.success(t('videoEditor.assetAdded'))
    },
    onError: onErr(t('videoEditor.assetAddError')),
  })
}

// Remove an element from the video — free, no re-render.
export function useRemoveAsset(creativeId) {
  const { t } = useTranslation('studio')
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ key }) => videoScenesApi.removeAsset(creativeId, { key }),
    onSuccess: (data) => {
      if (data.assets) qc.setQueryData(['video-assets', creativeId], { assets: data.assets })
      toast.success(t('videoEditor.assetRemoved'))
    },
    onError: onErr(t('videoEditor.assetRemoveError')),
  })
}
