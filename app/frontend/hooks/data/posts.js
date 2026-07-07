import { useQuery, useInfiniteQuery, keepPreviousData } from '@tanstack/react-query'
import { approvalsApi, postsApi } from '@/api'
import { keys } from '@/api/queryKeys'

// Public (login-less) client approval bundle — the path token is the credential.
export const usePublicApproval = (token) =>
  useQuery({ queryKey: keys.publicApproval(token), queryFn: () => approvalsApi.get(token), enabled: !!token })

// The posts hub. `usePosts` is the infinite-scroll list; `usePost` a single
// detail; `usePostsOverview` the analytics header (KPIs + breakdowns).
export const usePosts = (filters = {}) =>
  useInfiniteQuery({
    queryKey: keys.posts(filters),
    queryFn: ({ pageParam = 1 }) => postsApi.list({ ...filters, page: pageParam, per: 30 }),
    initialPageParam: 1,
    getNextPageParam: (last, pages) => (last?.meta?.has_more ? pages.length + 1 : undefined),
    placeholderData: keepPreviousData,
  })

export const usePost = (id) =>
  useQuery({ queryKey: keys.post(id), queryFn: () => postsApi.get(id), select: (d) => d.post, enabled: !!id })

export const usePostsOverview = (filters = {}) =>
  useQuery({ queryKey: keys.postsOverview(filters), queryFn: () => postsApi.overview(filters), select: (d) => d.overview })
