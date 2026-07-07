import { Link } from 'react-router-dom'
import { Card } from '@/components/ui/card'
import { MediaThumb } from '@/components/ui/media-thumb'
import { compact } from '@/lib/formatters'

// The responsive grid of post cards. Each card thumbnails the post's creative
// and links to its detail page.
export default function PostList({ posts = [] }) {
  if (!posts.length) return <p className="py-12 text-center text-ink-muted">Nenhuma publicação neste filtro.</p>
  return (
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
      {posts.map((p) => (
        <Link key={p.id} to={`/publicacoes/${p.id}`}>
          <Card className="overflow-hidden transition hover:border-brand/40">
            <div className="aspect-square w-full bg-surface-muted">
              <MediaThumb url={p.thumbnail_url} />
            </div>
            <div className="p-3">
              <p className="truncate text-sm font-semibold text-ink">{p.client_name} · {p.campaign_name}</p>
              <p className="text-xs text-ink-muted">{p.provider} · {p.status} · {p.creative_type || '—'}</p>
              {p.metrics && <p className="mt-1 text-xs text-ink-muted">{compact(p.metrics.views)} views · {compact(p.metrics.engagement)} eng.</p>}
            </div>
          </Card>
        </Link>
      ))}
    </div>
  )
}
