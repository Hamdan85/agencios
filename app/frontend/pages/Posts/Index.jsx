import { useState } from 'react'
import { useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Megaphone } from 'lucide-react'
import { Page } from '@/components/ui/page'
import { PageHeader } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/feedback'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import { useUrlParam } from '@/hooks/useUrlState'
import { usePosts, usePostsOverview } from '@/hooks/useData'
import PostsPerformance from '@/components/posts/PostsPerformance'
import PostsFilterBar from '@/components/posts/PostsFilterBar'
import PostsSortSelect from '@/components/posts/PostsSortSelect'
import PostList from '@/components/posts/PostList'

// The posts hub, split into two tabs over a shared filter row: "Publicações" (the
// paginated grid, the base path) and "Desempenho" (the analytics dashboard, at
// `/publicacoes/desempenho`). Each tab is its own URL PATH — never a query string.
// Deep-linkable with `?client=<id>` (the client detail page links here); the list
// tab also carries its own sort in the URL (`?ordenar=`), separate from filters.
const PERF_PATH = '/publicacoes/desempenho'

export default function PostsIndex() {
  const { t } = useTranslation('posts')
  const location = useLocation()
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const initialClient = searchParams.get('client') || undefined
  const [filters, setFilters] = useState({ client_id: initialClient })
  const [ordenar, setOrdenar] = useUrlParam('ordenar')
  const sort = ordenar || 'recent'

  // The active tab is derived from the path; switching navigates the segment
  // while preserving the query string (client / ordenar).
  const tab = location.pathname === PERF_PATH ? 'desempenho' : 'publicacoes'
  const setTab = (value) => {
    const pathname = value === 'desempenho' ? PERF_PATH : '/publicacoes'
    navigate({ pathname, search: location.search }, { replace: true })
  }

  const { data: overview, isLoading: overviewLoading } = usePostsOverview(filters)
  const { data, isLoading, fetchNextPage, hasNextPage, isFetchingNextPage } = usePosts({ ...filters, sort })
  const posts = (data?.pages || []).flatMap((pg) => pg.posts || [])

  return (
    <Page>
      <PageHeader
        title={t('header.title')}
        icon={Megaphone}
        color="#0EA5E9"
        description={t('header.description')}
      />

      <Tabs value={tab} onValueChange={setTab}>
        <PostsFilterBar
          filters={filters}
          setFilters={setFilters}
          leading={
            <div className="min-w-0 flex-1">
              <TabsList>
                <TabsTrigger value="publicacoes">{t('tabs.posts')}</TabsTrigger>
                <TabsTrigger value="desempenho">{t('tabs.performance')}</TabsTrigger>
              </TabsList>
            </div>
          }
        />

        <TabsContent value="publicacoes">
          <div className="mb-4 flex justify-end">
            <PostsSortSelect
              value={sort}
              onChange={(v) => setOrdenar(v === 'recent' ? undefined : v, { replace: true })}
            />
          </div>
          {isLoading ? <Skeleton className="h-64 rounded-2xl" /> : <PostList posts={posts} />}
          {hasNextPage && (
            <div className="mt-6 flex justify-center">
              <Button variant="outline" onClick={() => fetchNextPage()} disabled={isFetchingNextPage}>
                {isFetchingNextPage ? t('loadMore.loading') : t('loadMore.button')}
              </Button>
            </div>
          )}
        </TabsContent>

        <TabsContent value="desempenho">
          <PostsPerformance overview={overview} loading={overviewLoading} />
        </TabsContent>
      </Tabs>
    </Page>
  )
}
