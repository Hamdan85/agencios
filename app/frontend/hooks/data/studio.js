import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query'
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
      toast.success(variables?.kind === 'video' ? 'Geração iniciada ✨' : 'Geração concluída ✨')
    },
    onError: onErr('Erro ao gerar criativo.'),
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

export function useCreativeMutations() {
  const qc = useQueryClient()
  const inv = () => qc.invalidateQueries({ queryKey: ['creatives'] })
  return {
    update: useMutation({
      mutationFn: ({ id, ...data }) => creativesApi.update(id, data),
      onSuccess: () => { inv(); toast.success('Criativo atualizado.') },
      onError: onErr('Erro ao atualizar criativo.'),
    }),
    destroy: useMutation({
      mutationFn: (id) => creativesApi.destroy(id),
      onSuccess: () => { inv(); toast.success('Criativo removido.') },
      onError: onErr('Erro ao remover criativo.'),
    }),
  }
}
