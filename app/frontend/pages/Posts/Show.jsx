import { useParams, Link } from 'react-router-dom'
import { ArrowLeft, ExternalLink } from 'lucide-react'
import { Page } from '@/components/ui/page'
import { Card } from '@/components/ui/card'
import { InlineSpinner } from '@/components/ui/feedback'
import { compact } from '@/lib/formatters'
import { usePost } from '@/hooks/useData'
import CreativeExperience from '@/components/creative/CreativeExperience'
import LineTrend from '@/components/ui/charts/LineTrend'

function Stat({ label, value }) {
  return (
    <Card className="p-4">
      <p className="text-xs text-ink-muted">{label}</p>
      <p className="mt-1 font-display text-xl font-bold text-ink">{value == null ? '—' : compact(value)}</p>
    </Card>
  )
}

// A single post: its creative rendered natively (CreativeExperience), the full
// metric stat grid, and — when there's history — an evolution chart. Reached
// from the /publicacoes grid.
export default function PostShow() {
  const { id } = useParams()
  const { data: post, isLoading } = usePost(id)
  if (isLoading) return <Page><div className="flex justify-center py-20"><InlineSpinner size={24} className="text-brand" /></div></Page>
  if (!post) return <Page><p className="py-20 text-center text-ink-muted">Publicação não encontrada.</p></Page>

  const m = post.metrics || {}
  return (
    <Page>
      <Link to="/publicacoes" className="mb-4 inline-flex items-center gap-1 text-sm text-ink-muted hover:text-ink">
        <ArrowLeft size={16} /> Publicações
      </Link>
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <div>
          {post.creative ? <CreativeExperience creative={post.creative} /> : <div className="aspect-square rounded-2xl bg-surface-muted" />}
          {post.caption && <p className="mt-3 whitespace-pre-wrap text-sm text-ink-secondary">{post.caption}</p>}
        </div>
        <div className="flex flex-col gap-4">
          <div>
            <h1 className="font-display text-xl font-bold text-ink">{post.campaign_name}</h1>
            <p className="text-sm text-ink-muted">{post.client_name} · {post.provider} · {post.status} · {post.creative_type || '—'}</p>
            {post.permalink && (
              <a href={post.permalink} target="_blank" rel="noreferrer" className="mt-1 inline-flex items-center gap-1 text-sm text-brand hover:underline">
                Ver no {post.provider} <ExternalLink size={14} />
              </a>
            )}
          </div>
          <div className="grid grid-cols-3 gap-3">
            <Stat label="Alcance" value={m.reach} />
            <Stat label="Views" value={m.views} />
            <Stat label="Curtidas" value={m.likes} />
            <Stat label="Comentários" value={m.comments} />
            <Stat label="Compart." value={m.shares} />
            <Stat label="Salvos" value={m.saves} />
          </div>
          {(post.metric_history || []).length > 1 && (
            <Card className="p-4">
              <p className="mb-2 text-sm font-semibold text-ink">Evolução</p>
              <LineTrend
                data={(post.metric_history || []).map((h) => ({ date: (h.captured_at || '').slice(0, 10), views: h.views, engagement: h.engagement }))}
                keys={['views', 'engagement']}
              />
            </Card>
          )}
        </div>
      </div>
    </Page>
  )
}
