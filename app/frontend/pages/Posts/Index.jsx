import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Megaphone } from 'lucide-react'
import { Page } from '@/components/ui/page'
import { PageHeader } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { usePosts, usePostsOverview } from '@/hooks/useData'
import PostsAnalyticsHeader from '@/components/posts/PostsAnalyticsHeader'
import PostsFilterBar from '@/components/posts/PostsFilterBar'
import PostList from '@/components/posts/PostList'

// The posts hub: an analytics header over the current filter window, a filter
// row, and the paginated grid of every post the workspace has scheduled or
// published. Deep-linkable with `?client=<id>` (the client detail page links here).
export default function PostsIndex() {
  const [searchParams] = useSearchParams()
  const initialClient = searchParams.get('client') || undefined
  const [filters, setFilters] = useState({ client_id: initialClient })
  const { data: overview, isLoading: overviewLoading } = usePostsOverview(filters)
  const { data, isLoading, fetchNextPage, hasNextPage, isFetchingNextPage } = usePosts(filters)
  const posts = (data?.pages || []).flatMap((pg) => pg.posts || [])

  return (
    <Page>
      <PageHeader
        title="Publicações"
        icon={Megaphone}
        color="#0EA5E9"
        description="Tudo que foi agendado e publicado, com o desempenho de cada rede."
      />
      <PostsAnalyticsHeader overview={overview} loading={overviewLoading} />
      <PostsFilterBar filters={filters} setFilters={setFilters} />
      {isLoading ? <div className="h-64 animate-pulse rounded-2xl bg-surface-muted" /> : <PostList posts={posts} />}
      {hasNextPage && (
        <div className="mt-6 flex justify-center">
          <Button variant="outline" onClick={() => fetchNextPage()} disabled={isFetchingNextPage}>
            {isFetchingNextPage ? 'Carregando…' : 'Carregar mais'}
          </Button>
        </div>
      )}
    </Page>
  )
}
