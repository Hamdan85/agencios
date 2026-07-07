import { Link } from 'react-router-dom'
import { Eye, Heart, MessageCircle, BarChart3, CalendarClock, Megaphone } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { MediaThumb } from '@/components/ui/media-thumb'
import { EmptyState } from '@/components/ui/feedback'
import { PostStatusPill, NetworkBadge, CreativeTypeChip } from '@/components/ui/iconography'
import { compact, relativeDay, shortDt } from '@/lib/formatters'

// One compact metric readout: icon + value in the network/brand-neutral ink tone.
function Metric({ icon: Icon, value, label }) {
  return (
    <div className="flex flex-col items-center gap-0.5" title={label}>
      <Icon size={13} strokeWidth={2.2} className="text-ink-muted" />
      <span className="font-display text-sm font-bold tabular-nums text-ink">{compact(value ?? 0)}</span>
    </div>
  )
}

// The date footer — "Agendado · {shortDt}" for queued posts, a relative day
// (with tone tint) for everything already live.
function DateLine({ post }) {
  if (post.status === 'scheduled') {
    return (
      <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-ink-muted">
        <CalendarClock size={12} strokeWidth={2.2} />
        Agendado · {shortDt(post.scheduled_at)}
      </span>
    )
  }
  const rel = relativeDay(post.published_at || post.scheduled_at)
  return (
    <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-ink-muted">
      <CalendarClock size={12} strokeWidth={2.2} />
      {rel ? rel.text : '—'}
    </span>
  )
}

// The responsive grid of post cards. Each card surfaces — at a glance and without
// reading raw text — the network, lifecycle status, creative format, campaign and
// a compact performance readout, then links to its detail page.
export default function PostList({ posts = [] }) {
  if (!posts.length) {
    return (
      <EmptyState
        icon={Megaphone}
        title="Nenhuma publicação"
        description="Nenhuma publicação neste filtro."
      />
    )
  }
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {posts.map((p) => {
        const m = p.metrics
        return (
          <Link key={p.id} to={`/publicacoes/${p.id}`} className="group">
            <Card className="flex h-full flex-col overflow-hidden transition group-hover:-translate-y-0.5 group-hover:border-brand/40 group-hover:shadow-[0_1px_2px_rgba(24,18,43,0.06),0_16px_32px_-20px_rgba(24,18,43,0.24)]">
              {/* Media area with floating identity chips */}
              <div className="relative aspect-4/5 w-full overflow-hidden bg-surface-muted">
                {p.thumbnail_url ? (
                  <MediaThumb url={p.thumbnail_url} className="transition duration-500 group-hover:scale-[1.03]" />
                ) : (
                  <div className="flex size-full items-center justify-center">
                    <Megaphone size={36} strokeWidth={1.6} className="text-ink-muted/40" />
                  </div>
                )}
                {/* Legibility scrim so overlay chips read over any image */}
                <div className="pointer-events-none absolute inset-x-0 top-0 h-16 bg-linear-to-b from-black/35 to-transparent" />
                <div className="absolute inset-x-2 top-2 flex items-start justify-between gap-2">
                  <NetworkBadge
                    provider={p.provider}
                    username={p.username}
                    withLabel={false}
                    size={15}
                    className="bg-white/90 shadow-sm backdrop-blur-sm dark:bg-black/50"
                  />
                  <PostStatusPill status={p.status} size="sm" className="shadow-sm backdrop-blur-sm" />
                </div>
                {p.creative_type && (
                  <div className="absolute inset-x-2 bottom-2 flex">
                    <CreativeTypeChip type={p.creative_type} className="bg-white/90 shadow-sm backdrop-blur-sm dark:bg-black/50" />
                  </div>
                )}
              </div>

              {/* Body */}
              <div className="flex flex-1 flex-col gap-2.5 p-3.5">
                {/* Campaign line */}
                <div className="min-w-0">
                  <div className="flex items-center gap-1.5">
                    <span
                      className="size-2 shrink-0 rounded-full"
                      style={{ background: p.campaign_color || '#8B86A3' }}
                    />
                    <span className="truncate text-sm font-semibold text-ink">{p.campaign_name || 'Sem campanha'}</span>
                  </div>
                  {p.client_name && (
                    <p className="mt-0.5 truncate pl-3.5 text-xs text-ink-muted">{p.client_name}</p>
                  )}
                </div>

                {/* Metric strip / fallback */}
                <div className="mt-auto border-t border-border/60 pt-2.5">
                  {m ? (
                    <div className="grid grid-cols-4 gap-1">
                      <Metric icon={BarChart3} value={m.views} label="Visualizações" />
                      <Metric icon={Eye} value={m.reach} label="Alcance" />
                      <Metric icon={Heart} value={m.likes} label="Curtidas" />
                      <Metric icon={MessageCircle} value={m.comments} label="Comentários" />
                    </div>
                  ) : (
                    <p className="text-center text-[11px] font-semibold text-ink-muted">Aguardando métricas</p>
                  )}
                </div>

                {/* Date footer */}
                <div className="flex items-center justify-between">
                  <DateLine post={p} />
                </div>
              </div>
            </Card>
          </Link>
        )
      })}
    </div>
  )
}
