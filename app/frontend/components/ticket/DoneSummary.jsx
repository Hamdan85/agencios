import { useMemo } from 'react'
import { Link } from 'react-router-dom'
import { Card } from '@/components/ui/card'
import { Markdown } from '@/components/ui/markdown'
import { Badge, ColorBadge } from '@/components/ui/badge'
import { IconTile } from '@/components/ui/icon-tile'
import { SectionLabel } from '@/components/ui/section-label'
import { ChannelIcons, CreativeTypeChip } from '@/components/ui/iconography'
import { dt, num } from '@/lib/formatters'
import {
  CheckCircle2, Clock, ListChecks, Send, Target, Users, Hash, Repeat, ThumbsUp,
  AlertTriangle, Sparkles, ExternalLink, GitBranch, Eye, Heart, MessageCircle,
  Share2, Bookmark, BarChart3, FileText,
} from 'lucide-react'

const DONE = '#14B8A6'

const METRIC_TILES = [
  { key: 'reach', label: 'Alcance', icon: Eye, color: '#0EA5E9' },
  { key: 'views', label: 'Views', icon: BarChart3, color: '#7C3AED' },
  { key: 'likes', label: 'Curtidas', icon: Heart, color: '#EC4899' },
  { key: 'comments', label: 'Comentários', icon: MessageCircle, color: '#F59E0B' },
  { key: 'shares', label: 'Compart.', icon: Share2, color: '#10B981' },
  { key: 'saves', label: 'Salvos', icon: Bookmark, color: '#6366F1' },
]

// The engagement breakdown bar — the "gráfico" of how people interacted.
const ENGAGEMENT = [
  { key: 'likes', label: 'Curtidas', color: '#EC4899' },
  { key: 'comments', label: 'Comentários', color: '#F59E0B' },
  { key: 'shares', label: 'Compart.', color: '#10B981' },
  { key: 'saves', label: 'Salvos', color: '#6366F1' },
]

const REPEAT_META = {
  repeat: { label: 'Repetir', color: '#10B981', hint: 'Vale rodar de novo como está' },
  iterate: { label: 'Iterar', color: '#6366F1', hint: 'Vale repetir com ajustes' },
  retire: { label: 'Aposentar', color: '#8B86A3', hint: 'Não vale repetir' },
}

const fmt = (n) => (n != null ? num(n) : '—')

function daysBetween(a, b) {
  if (!a) return null
  const start = new Date(a).getTime()
  const end = b ? new Date(b).getTime() : Date.now()
  if (Number.isNaN(start) || Number.isNaN(end)) return null
  return Math.max(0, Math.round((end - start) / 86_400_000))
}

function StatChip({ icon: Icon, label, value }) {
  return (
    <div className="flex items-center gap-2 rounded-xl bg-white/70 px-3 py-2 ring-1 ring-black/5 backdrop-blur dark:bg-white/10">
      <Icon size={15} style={{ color: DONE }} />
      <div className="leading-tight">
        <p className="font-display text-sm font-extrabold text-ink">{value}</p>
        <SectionLabel className="text-[10px] font-semibold tracking-wide">{label}</SectionLabel>
      </div>
    </div>
  )
}

function SectionCard({ icon: Icon, color = DONE, title, children, action }) {
  return (
    <Card className="overflow-hidden animate-rise">
      <div className="flex items-center gap-2.5 border-b border-border p-4" style={{ background: `${color}08` }}>
        <IconTile icon={Icon} color={color} size="xs" tint="18" strokeWidth={2.3} />
        <h3 className="font-display text-sm font-bold text-ink">{title}</h3>
        {action && <div className="ml-auto">{action}</div>}
      </div>
      <div className="p-4">{children}</div>
    </Card>
  )
}

function Bullets({ items, icon: Icon, color }) {
  if (!items?.length) return null
  return (
    <ul className="space-y-1.5">
      {items.map((it, i) => (
        <li key={i} className="flex items-start gap-2 text-sm text-ink-secondary">
          <Icon size={14} className="mt-0.5 shrink-0" style={{ color }} />
          <span>{it}</span>
        </li>
      ))}
    </ul>
  )
}

export default function DoneSummary({ ticket, posts = [], subtasks = [] }) {
  const ideation = ticket?.fields?.ideation || {}
  const production = ticket?.fields?.production || {}
  const retro = ticket?.fields?.retrospective || {}
  const summary = ticket?.ai_summaries?.done

  // Aggregate metrics across every published post.
  const agg = useMemo(() => {
    return (posts || []).reduce((acc, p) => {
      const m = p.metrics || {}
      METRIC_TILES.forEach((t) => { acc[t.key] = (acc[t.key] || 0) + (Number(m[t.key]) || 0) })
      return acc
    }, {})
  }, [posts])

  const engagementTotal = ENGAGEMENT.reduce((s, e) => s + (agg[e.key] || 0), 0)
  const hasPosts = (posts || []).length > 0
  const subDone = subtasks.filter((s) => s.done).length
  const days = daysBetween(ticket?.created_at, ticket?.published_at)
  const rec = REPEAT_META[retro.repeat_recommendation]
  const hashtags = Array.isArray(production.hashtags) ? production.hashtags : []

  return (
    <div className="space-y-5">
      {/* ── Hero ── */}
      <div
        className="relative overflow-hidden rounded-2xl border p-5 animate-rise"
        style={{ borderColor: `${DONE}33`, background: `linear-gradient(135deg, ${DONE}1A, ${DONE}08 55%, transparent)` }}
      >
        <div className="pointer-events-none absolute -right-10 -top-12 size-40 rounded-full opacity-[0.12]" style={{ background: DONE }} />
        <div className="relative">
          <div className="flex items-center gap-2.5">
            <div className="flex size-10 items-center justify-center rounded-xl shadow-sm" style={{ background: DONE, color: '#fff' }}>
              <CheckCircle2 size={20} strokeWidth={2.4} />
            </div>
            <div>
              <p className="text-[11px] font-bold uppercase tracking-[0.14em]" style={{ color: DONE }}>Concluído</p>
              <p className="text-xs font-medium text-ink-muted">Retrospecto completo deste ticket</p>
            </div>
          </div>

          <h2 className="mt-3 font-display text-xl font-extrabold leading-tight tracking-tight text-ink sm:text-2xl">
            {ticket?.display_title || ticket?.title}
          </h2>

          <div className="mt-2 flex flex-wrap items-center gap-2">
            {ticket?.creative_type && <CreativeTypeChip type={ticket.creative_type} />}
            {ticket?.channels?.length > 0 && <ChannelIcons channels={ticket.channels} size={14} />}
          </div>

          <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
            {days != null && <StatChip icon={Clock} label="Dias no funil" value={days} />}
            <StatChip icon={Send} label="Publicações" value={fmt((posts || []).length)} />
            <StatChip icon={ListChecks} label="Subtarefas" value={`${subDone}/${subtasks.length}`} />
            <StatChip icon={Eye} label="Alcance total" value={fmt(agg.reach)} />
          </div>
        </div>
      </div>

      {/* ── AI case-study summary ── */}
      {summary && (
        <SectionCard icon={Sparkles} title="Resumo da IA">
          <Markdown className="text-[15px]">{summary}</Markdown>
        </SectionCard>
      )}

      {/* ── Aggregate performance + engagement graphic ── */}
      <SectionCard icon={BarChart3} color="#7C3AED" title="Desempenho consolidado">
        {!hasPosts ? (
          <p className="rounded-xl border border-dashed border-border bg-surface-muted/40 px-4 py-6 text-center text-sm text-ink-muted">
            Nenhuma publicação registrada para este ticket.
          </p>
        ) : (
          <div className="space-y-4">
            <div className="grid grid-cols-3 gap-2 sm:grid-cols-6">
              {METRIC_TILES.map((t) => {
                const Icon = t.icon
                return (
                  <div key={t.key} className="rounded-xl border border-border bg-surface-muted/60 p-2.5 text-center">
                    <Icon size={15} strokeWidth={2.3} className="mx-auto" style={{ color: t.color }} />
                    <p className="mt-1 font-display text-base font-extrabold text-ink">{fmt(agg[t.key])}</p>
                    <SectionLabel className="text-[10px] font-semibold tracking-wide">{t.label}</SectionLabel>
                  </div>
                )
              })}
            </div>

            {engagementTotal > 0 && (
              <div>
                <div className="mb-2 flex items-center justify-between">
                  <SectionLabel className="text-xs tracking-wide">Composição do engajamento</SectionLabel>
                  <p className="font-mono text-xs font-bold text-ink-secondary">{fmt(engagementTotal)} interações</p>
                </div>
                <div className="flex h-3 overflow-hidden rounded-full ring-1 ring-border">
                  {ENGAGEMENT.map((e) => {
                    const v = agg[e.key] || 0
                    if (!v) return null
                    return <div key={e.key} style={{ width: `${(v / engagementTotal) * 100}%`, background: e.color }} title={`${e.label}: ${fmt(v)}`} />
                  })}
                </div>
                <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1">
                  {ENGAGEMENT.map((e) => (
                    <span key={e.key} className="inline-flex items-center gap-1.5 text-[11px] font-semibold text-ink-muted">
                      <span className="size-2 rounded-full" style={{ background: e.color }} />
                      {e.label} · {fmt(agg[e.key] || 0)}
                    </span>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}
      </SectionCard>

      {/* ── Per-post breakdown ── */}
      {hasPosts && (
        <SectionCard icon={Send} color="#10B981" title="Por publicação">
          <div className="space-y-3">
            {posts.map((post) => (
              <div key={post.id} className="rounded-xl border border-border bg-surface p-3.5">
                <div className="mb-2.5 flex flex-wrap items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <ChannelIcons channels={post.provider ? [post.provider] : []} size={14} />
                    <span className="text-sm font-semibold text-ink">{post.username || post.provider || 'Publicação'}</span>
                    <span className="text-xs text-ink-muted">· {dt(post.published_at || post.scheduled_at)}</span>
                  </div>
                  {post.permalink && (
                    <a href={post.permalink} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-xs font-bold text-brand hover:underline">
                      Ver post <ExternalLink size={12} />
                    </a>
                  )}
                </div>
                <div className="grid grid-cols-3 gap-2 sm:grid-cols-6">
                  {METRIC_TILES.map((t) => (
                    <div key={t.key} className="rounded-lg bg-surface-muted/60 p-2 text-center">
                      <p className="font-display text-sm font-extrabold text-ink">{fmt(post.metrics?.[t.key])}</p>
                      <SectionLabel className="text-[9px] font-semibold tracking-wide">{t.label}</SectionLabel>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </SectionCard>
      )}

      {/* ── Content recap ── */}
      {(ideation.objective || ideation.target_persona || production.caption) && (
        <SectionCard icon={FileText} color="#0EA5E9" title="O conteúdo">
          <div className="space-y-3.5">
            {ideation.objective && (
              <div className="flex items-start gap-2">
                <Target size={15} className="mt-0.5 shrink-0 text-sky" />
                <div>
                  <SectionLabel className="tracking-wide text-ink-faint">Objetivo</SectionLabel>
                  <p className="text-sm text-ink-secondary">{ideation.objective}</p>
                </div>
              </div>
            )}
            {ideation.target_persona && (
              <div className="flex items-start gap-2">
                <Users size={15} className="mt-0.5 shrink-0 text-sky" />
                <div>
                  <SectionLabel className="tracking-wide text-ink-faint">Persona-alvo</SectionLabel>
                  <p className="text-sm text-ink-secondary">{ideation.target_persona}</p>
                </div>
              </div>
            )}
            {production.caption && (
              <div>
                <SectionLabel className="mb-1 tracking-wide text-ink-faint">Legenda publicada</SectionLabel>
                <p className="whitespace-pre-wrap rounded-xl bg-surface-muted/60 p-3 text-sm text-ink-secondary">{production.caption}</p>
              </div>
            )}
            {hashtags.length > 0 && (
              <div className="flex flex-wrap gap-1.5">
                {hashtags.map((h, i) => (
                  <Badge key={i} className="gap-0.5 bg-brand/10 px-2 font-semibold tracking-normal text-brand">
                    <Hash size={11} />{String(h).replace(/^#/, '')}
                  </Badge>
                ))}
              </div>
            )}
          </div>
        </SectionCard>
      )}

      {/* ── Retrospective ── */}
      {(rec || retro.wins?.length || retro.improvements?.length || retro.lessons_learned) && (
        <SectionCard
          icon={Repeat}
          color="#6366F1"
          title="Retrospectiva"
          action={rec && (
            <ColorBadge color={rec.color} solid className="py-1" title={rec.hint}>
              <Repeat size={12} /> {rec.label}
            </ColorBadge>
          )}
        >
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            {retro.wins?.length > 0 && (
              <div>
                <SectionLabel className="mb-2 tracking-wide text-ink-faint">Vitórias</SectionLabel>
                <Bullets items={retro.wins} icon={ThumbsUp} color="#10B981" />
              </div>
            )}
            {retro.improvements?.length > 0 && (
              <div>
                <SectionLabel className="mb-2 tracking-wide text-ink-faint">Melhorias</SectionLabel>
                <Bullets items={retro.improvements} icon={AlertTriangle} color="#F59E0B" />
              </div>
            )}
          </div>
          {retro.lessons_learned && (
            <div className="mt-4 border-t border-border pt-4">
              <SectionLabel className="mb-2 tracking-wide text-ink-faint">Lições aprendidas</SectionLabel>
              <div
                className="prose prose-sm max-w-none text-ink-secondary prose-strong:text-ink"
                dangerouslySetInnerHTML={{ __html: retro.lessons_learned }}
              />
            </div>
          )}
        </SectionCard>
      )}

      {/* ── Related tickets ── */}
      {ticket?.relations?.length > 0 && (
        <SectionCard icon={GitBranch} color="#7C3AED" title="Tickets relacionados">
          <div className="space-y-1.5">
            {ticket.relations.map((r) => (
              <Link
                key={`${r.kind}-${r.ticket_id}`}
                to={`/tickets/${r.ticket_id}`}
                className="flex items-center gap-2 rounded-lg px-2 py-1.5 transition hover:bg-surface-muted"
              >
                <span className="shrink-0 rounded-md bg-brand/12 px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-brand">{r.label}</span>
                <span className="truncate text-sm text-ink-secondary">{r.title}</span>
              </Link>
            ))}
          </div>
        </SectionCard>
      )}
    </div>
  )
}
