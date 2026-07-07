import { Link } from 'react-router-dom'
import {
  Briefcase, Ticket, ExternalLink, CalendarClock, Radio, EyeOff, AlertTriangle, ChevronRight,
} from 'lucide-react'
import { PostStatusPill, NetworkBadge, CreativeTypeChip } from '@/components/ui/iconography'
import { channelMeta } from '@/lib/constants'
import { dt, timeAgo } from '@/lib/formatters'

// A single linked entity chip in the hero — an icon/avatar, a label, and a
// trailing chevron that signals it navigates. Renders as a Link (internal) or an
// <a> (external permalink).
function EntityChip({ to, href, children }) {
  const cls =
    'group inline-flex items-center gap-2 rounded-full border border-border bg-surface/70 px-3 py-1.5 text-xs font-semibold text-ink-secondary shadow-sm backdrop-blur transition hover:border-brand/40 hover:text-ink'
  const inner = (
    <>
      {children}
      <ChevronRight size={13} className="shrink-0 text-ink-faint transition group-hover:translate-x-0.5 group-hover:text-brand" />
    </>
  )
  if (href) {
    return (
      <a href={href} target="_blank" rel="noreferrer" className={cls}>
        {inner}
      </a>
    )
  }
  return (
    <Link to={to} className={cls}>
      {inner}
    </Link>
  )
}

// A timestamp line with a tinted icon.
function TimeLine({ icon: Icon, color, label }) {
  return (
    <span className="inline-flex items-center gap-1.5 text-xs font-medium text-ink-muted">
      <Icon size={13} strokeWidth={2.3} style={{ color }} />
      {label}
    </span>
  )
}

// The post-detail hero: a network-colored wash carrying the network identity,
// lifecycle status, creative type, the ticket title as H1, a row of linked
// entity chips (client / campaign / ticket / external permalink), the relevant
// lifecycle timestamps, and — when the post failed — a danger callout.
export default function PostDetailHeader({ post }) {
  const net = channelMeta(post.provider)
  const accent = net.color

  return (
    <div
      className="relative overflow-hidden rounded-2xl border p-5 animate-rise sm:p-6"
      style={{ borderColor: `${accent}33`, background: `linear-gradient(135deg, ${accent}1A, ${accent}08 55%, transparent)` }}
    >
      <div className="pointer-events-none absolute -right-12 -top-14 size-44 rounded-full opacity-[0.12]" style={{ background: accent }} />

      <div className="relative">
        {/* Identity row */}
        <div className="flex flex-wrap items-center gap-2">
          <NetworkBadge provider={post.provider} username={post.username} size={15} />
          <PostStatusPill status={post.status} />
          {post.creative_type && <CreativeTypeChip type={post.creative_type} />}
        </div>

        {/* Title */}
        <h1 className="mt-3 font-display text-2xl font-extrabold leading-tight tracking-tight text-ink sm:text-3xl">
          {post.ticket_title || post.campaign_name || 'Publicação'}
        </h1>

        {/* Linked entity chips */}
        <div className="mt-4 flex flex-wrap items-center gap-2">
          {post.client_id && (
            <EntityChip to={`/clientes/${post.client_id}`}>
              {post.client_logo_url ? (
                <img src={post.client_logo_url} alt="" className="size-5 shrink-0 rounded-md object-cover ring-1 ring-black/5" />
              ) : (
                <span className="flex size-5 shrink-0 items-center justify-center rounded-md bg-brand/12 text-brand">
                  <Briefcase size={12} strokeWidth={2.4} />
                </span>
              )}
              <span className="max-w-[10rem] truncate">{post.client_name || 'Cliente'}</span>
            </EntityChip>
          )}

          {post.campaign_id && (
            <EntityChip to={`/campanhas/${post.campaign_id}`}>
              <span className="size-2.5 shrink-0 rounded-full ring-2 ring-white/70 dark:ring-white/10" style={{ background: post.campaign_color || '#7C3AED' }} />
              <span className="max-w-[12rem] truncate">{post.campaign_name || 'Campanha'}</span>
            </EntityChip>
          )}

          {post.ticket_id && (
            <EntityChip to={`/tickets/${post.ticket_id}`}>
              <Ticket size={13} strokeWidth={2.3} className="shrink-0 text-brand" />
              Ver ticket
            </EntityChip>
          )}

          {post.permalink && (
            <EntityChip href={post.permalink}>
              <ExternalLink size={13} strokeWidth={2.3} className="shrink-0" style={{ color: accent }} />
              Ver no {net.label}
            </EntityChip>
          )}
        </div>

        {/* Lifecycle timestamps */}
        <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1.5">
          {post.scheduled_at && (
            <TimeLine icon={CalendarClock} color="#F59E0B" label={`Agendado para ${dt(post.scheduled_at)}`} />
          )}
          {post.published_at && (
            <TimeLine icon={Radio} color="#10B981" label={`Publicado ${timeAgo(post.published_at)}`} />
          )}
          {post.unpublished_at && (
            <TimeLine icon={EyeOff} color="#8B86A3" label={`Despublicado ${timeAgo(post.unpublished_at)}`} />
          )}
        </div>

        {/* Failure callout */}
        {post.status === 'failed' && (
          <div className="mt-4 flex items-start gap-2.5 rounded-xl border border-danger/25 bg-danger/8 p-3.5">
            <AlertTriangle size={17} strokeWidth={2.4} className="mt-0.5 shrink-0 text-danger" />
            <div className="min-w-0">
              <p className="text-sm font-bold text-danger">A publicação falhou</p>
              {post.failure_reason && (
                <p className="mt-0.5 whitespace-pre-wrap break-words text-sm text-ink-secondary">{post.failure_reason}</p>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
