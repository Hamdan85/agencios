import { useQuery, useInfiniteQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import { studioApi, generationsApi, creativesApi } from '@/api'
import { keys } from '@/api/queryKeys'
import analytics, { EVENTS } from '@/lib/analytics'
import { onErr } from './shared'

// ── Studio / generations ───────────────────────────────────────
export const useStudio = () => useQuery({ queryKey: keys.studio(), queryFn: studioApi.get })
export const useGenerations = (filters = {}) =>
  useQuery({ queryKey: keys.generations(filters), queryFn: () => generationsApi.list(filters), select: (d) => d.generations })

export function useGenerate() {
  const { t } = useTranslation('studio')
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ kind, params }) => studioApi.generate(kind, params),
    onSuccess: (_data, variables) => {
      qc.invalidateQueries({ queryKey: keys.studio() })
      qc.invalidateQueries({ queryKey: ['generations'] })
      qc.invalidateQueries({ queryKey: ['creatives'] })
      qc.invalidateQueries({ queryKey: ['tickets'] })
      // Activation + usage tracking (video/image/carousel all consume credits).
      analytics.track(EVENTS.CREATIVE_GENERATED, { kind: variables?.kind, source: 'studio' })
      // Video runs async (storyboard + render off-request) — it only STARTED here.
      toast.success(variables?.kind === 'video' ? t('toasts.generateStartedVideo') : t('toasts.generateDone'))
    },
    onError: onErr(t('toasts.generateError')),
  })
}

// ── Workspace creatives (Studio gallery) ──────────────────────
// `enabled` lets callers that only need this on demand (e.g. a picker dialog
// that opens lazily) skip the fetch until then.
export const useWorkspaceCreatives = (filters = {}, { enabled = true } = {}) =>
  useQuery({
    queryKey: keys.creatives(filters),
    queryFn: () => creativesApi.list(filters),
    placeholderData: keepPreviousData,
    enabled,
  })

// Paginated (infinite-scroll) variant for the Studio gallery — the library can
// grow unbounded, so it loads a page at a time as the user scrolls. The backend
// returns `{ creatives, next_page, clients }`; `clients` is the same on every
// page (read off page 1). Shares the `['creatives', filters]` key family so the
// generation broadcasts / mutations that invalidate `['creatives']` refresh it.
export const useWorkspaceCreativesInfinite = (filters = {}) =>
  useInfiniteQuery({
    queryKey: keys.creatives({ ...filters, infinite: true }),
    queryFn: ({ pageParam = 1 }) => creativesApi.list({ ...filters, page: pageParam }),
    initialPageParam: 1,
    getNextPageParam: (last) => last?.next_page ?? undefined,
    placeholderData: keepPreviousData,
  })

export function useCreativeMutations() {
  const { t } = useTranslation('studio')
  const qc = useQueryClient()
  const inv = () => qc.invalidateQueries({ queryKey: ['creatives'] })
  return {
    update: useMutation({
      mutationFn: ({ id, ...data }) => creativesApi.update(id, data),
      onSuccess: () => { inv(); toast.success(t('toasts.creativeUpdated')) },
      onError: onErr(t('toasts.creativeUpdateError')),
    }),
    destroy: useMutation({
      mutationFn: (id) => creativesApi.destroy(id),
      onSuccess: () => { inv(); toast.success(t('toasts.creativeRemoved')) },
      onError: onErr(t('toasts.creativeRemoveError')),
    }),
  }
}
