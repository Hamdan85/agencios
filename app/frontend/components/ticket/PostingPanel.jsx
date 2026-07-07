import { lazy, Suspense, useEffect, useMemo, useRef, useState } from 'react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { IconTile } from '@/components/ui/icon-tile'
import { MediaThumb } from '@/components/ui/media-thumb'
import { Spinner, EmptyState, AiRewritingOverlay } from '@/components/ui/feedback'
import { DateTimePicker } from '@/components/ui/date-picker'
import { ChannelIcons } from '@/components/ui/iconography'
import { creativeMeta, channelMeta, creativeMediaKind, resolvePostRouting, isCoverType } from '@/lib/constants'
import AiFillButton from './AiFillButton'
import { dt } from '@/lib/formatters'
import { cn } from '@/lib/utils'
import {
  Send, Clock, Zap, MessageCircle, MessageSquareText, Link2, CheckCircle2, AlertCircle, Loader2, ImagePlus, Radio, Ban, Eye, ChevronDown, ChevronUp, CalendarX2,
} from 'lucide-react'

const MediaViewer = lazy(() => import('./MediaViewer'))

const MEDIA_LABEL = { image: 'imagem', carousel: 'carrossel', video: 'vídeo', text: 'texto' }

// A generated asset is a video when its URL carries a video extension (the
// ActiveStorage blob URL keeps the original filename, e.g. .../video-80.mp4).
const isVideoUrl = (url) => /\.(mp4|mov|webm|avi)(\?|$)/i.test(url || '')

// Turn a creative's asset_urls into MediaViewer attachment objects so a creative
// in the posting bundle can be previewed full-size, not just selected.
function creativeToAttachments(creative) {
  const m = creativeMeta(creative?.creative_type)
  return (creative?.asset_urls || []).map((url, i) => {
    const isVideo = isVideoUrl(url)
    return {
      id: `${creative.id}-${i}`,
      url,
      filename: `${m.label}-${creative.id}-${i + 1}`,
      display_name: creative.name || m.label,
      kind: isVideo ? 'video' : 'image',
      content_type: isVideo ? 'video/mp4' : 'image/jpeg',
      description: creative.caption || undefined,
    }
  })
}

const POST_STATUS = {
  scheduled:   { label: 'Agendado',    variant: 'muted',   icon: Clock },
  publishing:  { label: 'Publicando…', variant: 'warning', icon: Loader2 },
  published:   { label: 'No ar',       variant: 'success', icon: CheckCircle2 },
  failed:      { label: 'Falhou',      variant: 'danger',  icon: AlertCircle },
  unpublished: { label: 'Despublicado', variant: 'muted',  icon: Ban },
}

// The "Postagem" step: pick ONE creative per scoped type, choose immediate vs
// scheduled, and publish. On publish, each creative routes to the channels that
// support its media; a cover/thumbnail image rides the video where supported.
// The ticket only reaches "No ar" when a post actually succeeds.
export default function PostingPanel({
  ticket, creatives = [], posts = [], onSave, onPublish, publishing = false,
  onAiAction, acting = false, filling = false, onUnpublish, unpublishingId,
  onCancelPost, cancelingId, color = '#EC4899',
}) {
  const fields = ticket?.fields?.scheduled || {}
  const channels = Array.isArray(ticket?.channels) ? ticket.channels : []
  const ready = creatives.filter((c) => c?.status === 'ready' && (c?.asset_urls?.length || 0) > 0)

  // The types scoped in Escopo (mirrored column → scoping field bag), plus any
  // extra type that already has a ready creative so nothing is hidden.
  const displayTypes = useMemo(() => {
    const scoped = Array.isArray(ticket?.creative_types) && ticket.creative_types.length
      ? ticket.creative_types
      : (Array.isArray(ticket?.fields?.scoping?.creative_types) ? ticket.fields.scoping.creative_types : [])
    const readyTypes = ready.map((c) => c.creative_type)
    return [...new Set([...scoped, ...readyTypes])].filter(Boolean)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ticket?.id, JSON.stringify(ticket?.creative_types), ready.length])

  // The scheduled moment is the ticket's `scheduled_at` column (mirrored from
  // this field bag on save, and also editable from the ticket's "Agendado"
  // detail row) — fall back to it so both surfaces show the same value.
  const initialScheduledAt = fields.scheduled_at || ticket?.scheduled_at
  const [selectedByType, setSelectedByType] = useState({})
  const [mode, setMode] = useState(fields.post_mode || (initialScheduledAt ? 'scheduled' : 'immediate'))
  const [scheduledAt, setScheduledAt] = useState(initialScheduledAt ? String(initialScheduledAt).slice(0, 16) : '')
  const [firstComment, setFirstComment] = useState(fields.first_comment || '')
  const [linkInBio, setLinkInBio] = useState(fields.link_in_bio || '')
  const baseCaption = ticket?.fields?.production?.caption || ''
  const [captionByChannel, setCaptionByChannel] = useState(fields.captions || {})
  const [expandedCaptions, setExpandedCaptions] = useState({})
  const [viewer, setViewer] = useState({ open: false, attachments: [] })

  const openViewer = (creative) => {
    const atts = creativeToAttachments(creative)
    if (atts.length) setViewer({ open: true, attachments: atts })
  }
  const toggleCaption = (channel) => setExpandedCaptions((prev) => ({ ...prev, [channel]: !prev[channel] }))

  // Re-seed the text drafts when switching to a different ticket (the panel may
  // not remount, so the useState initializers alone would go stale).
  useEffect(() => {
    setCaptionByChannel(fields.captions || {})
    setFirstComment(fields.first_comment || '')
    setLinkInBio(fields.link_in_bio || '')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ticket?.id])

  // An explicit "Atualizar campos com IA" must WIN over the local drafts: the fill
  // writes captions/first_comment server-side and broadcasts done — without this,
  // the fresh values land in `fields` but the state above never adopts them, so
  // the regenerate looks like it did nothing (same fix as FieldGroup's).
  const adoptAfterFill = useRef(false)
  useEffect(() => { if (filling) adoptAfterFill.current = true }, [filling])
  useEffect(() => {
    if (!adoptAfterFill.current) return
    adoptAfterFill.current = false
    setCaptionByChannel(fields.captions || {})
    setFirstComment(fields.first_comment || '')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [JSON.stringify(fields.captions), fields.first_comment])

  // Default each type's selection to the saved one, else the only ready creative
  // of that type.
  useEffect(() => {
    const savedIds = Array.isArray(fields.creative_ids)
      ? fields.creative_ids.map(String)
      : (fields.creative_id ? [String(fields.creative_id)] : [])
    const next = {}
    displayTypes.forEach((t) => {
      const group = ready.filter((c) => c.creative_type === t)
      const saved = group.find((c) => savedIds.includes(String(c.id)))
      if (saved) next[t] = String(saved.id)
      else if (group.length === 1) next[t] = String(group[0].id)
    })
    setSelectedByType(next)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ticket?.id, ready.length, displayTypes.length])

  const selectedCreatives = useMemo(
    () => displayTypes.map((t) => ready.find((c) => String(c.id) === selectedByType[t])).filter(Boolean),
    [displayTypes, ready, selectedByType],
  )
  const routing = useMemo(() => resolvePostRouting(selectedCreatives, channels), [selectedCreatives, channels])
  const anyPost = routing.some((r) => r.posts.length > 0)

  const saveField = (key, value) => onSave?.({ [key]: value })
  const toggle = (type, id) => setSelectedByType((prev) => ({ ...prev, [type]: prev[type] === id ? undefined : id }))
  const setChannelCaption = (channel, value) => setCaptionByChannel((prev) => ({ ...prev, [channel]: value }))
  const saveChannelCaption = () => saveField('captions', captionByChannel)

  const canPublish = selectedCreatives.length > 0 && anyPost && (mode === 'immediate' || !!scheduledAt) && !publishing

  const handlePublish = () => {
    if (!canPublish) return
    onPublish?.({
      creative_ids: selectedCreatives.map((c) => c.id),
      mode,
      scheduled_at: mode === 'scheduled' ? scheduledAt : undefined,
    })
  }

  return (
    <Card className="overflow-hidden animate-rise">
      <div className="flex items-center justify-between gap-3 border-b border-border p-5" style={{ background: `${color}0A` }}>
        <div className="flex min-w-0 flex-1 items-center gap-2.5">
          <IconTile icon={Send} color={color} size="sm" tint="1A" strokeWidth={2.3} />
          <div className="min-w-0">
            <h3 className="truncate font-display text-base font-bold text-ink">Postagem</h3>
            <p className="truncate text-xs text-ink-muted">Escolha um criativo por tipo e publique — agora ou agendado.</p>
          </div>
        </div>
        {onAiAction && <div className="shrink-0"><AiFillButton onClick={onAiAction} acting={acting} color={color} /></div>}
      </div>

      <AiRewritingOverlay active={filling} color={color}>
      <div className="space-y-5 p-5">
        {/* 1 — choose one creative per scoped type */}
        <div className="space-y-4">
          <Label className="flex items-center gap-1.5"><ImagePlus size={13} style={{ color }} /> Criativos a postar</Label>
          {displayTypes.length === 0 ? (
            <EmptyState
              icon={ImagePlus}
              title="Nenhum tipo definido"
              description="Volte ao Escopo e escolha os tipos de criativo deste ticket."
              color={color}
            />
          ) : (
            displayTypes.map((type) => {
              const tm = creativeMeta(type)
              const group = ready.filter((c) => c.creative_type === type)
              const TmIcon = tm.icon
              return (
                <div key={type} className="space-y-2">
                  <div className="flex items-center gap-1.5">
                    <span className="inline-flex items-center gap-1.5 rounded-lg px-2 py-0.5 text-xs font-bold" style={{ background: `${tm.color}18`, color: tm.color }}>
                      <TmIcon size={12} strokeWidth={2.4} /> {tm.label}
                    </span>
                    {isCoverType(type) && <span className="text-[11px] text-ink-faint">— vira capa do vídeo, ou post se não houver vídeo</span>}
                  </div>
                  {group.length === 0 ? (
                    <p className="rounded-xl border border-dashed border-border px-3.5 py-2.5 text-xs text-ink-faint">
                      Nenhum {tm.label.toLowerCase()} pronto — gere ou anexe um na Produção.
                    </p>
                  ) : (
                    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                      {group.map((c) => {
                        const active = selectedByType[type] === String(c.id)
                        const thumb = c.asset_urls?.[0]
                        const hasAssets = (c.asset_urls?.length || 0) > 0
                        return (
                          <div
                            key={c.id}
                            role="button"
                            tabIndex={0}
                            onClick={() => toggle(type, String(c.id))}
                            onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggle(type, String(c.id)) } }}
                            aria-pressed={active}
                            className={cn(
                              'group relative cursor-pointer overflow-hidden rounded-xl border-2 text-left transition-all',
                              active ? 'border-brand ring-2 ring-brand/20' : 'border-border hover:border-brand/40',
                            )}
                          >
                            <div className="relative w-full" style={{ paddingBottom: '100%' }}>
                              <div className="absolute inset-0 overflow-hidden" style={{ background: `${tm.color}10` }}>
                                {thumb ? (
                                  <MediaThumb url={thumb} alt={tm.label} />
                                ) : (
                                  <div className="flex size-full items-center justify-center"><TmIcon size={24} style={{ color: tm.color }} /></div>
                                )}
                                {active && (
                                  <div className="absolute right-1.5 top-1.5 grid size-5 place-items-center rounded-full bg-brand text-white shadow">
                                    <CheckCircle2 size={13} />
                                  </div>
                                )}
                                {/* View full-size — stops propagation so it never toggles selection.
                                    Always visible on touch, hover-revealed on desktop. */}
                                {hasAssets && (
                                  <button
                                    type="button"
                                    aria-label="Visualizar criativo"
                                    onClick={(e) => { e.stopPropagation(); openViewer(c) }}
                                    className="absolute left-1.5 top-1.5 z-10 grid size-6 place-items-center rounded-full bg-white/90 text-ink-muted shadow-sm backdrop-blur transition hover:bg-white hover:text-ink focus:outline-none sm:opacity-0 sm:group-hover:opacity-100"
                                  >
                                    <Eye size={13} />
                                  </button>
                                )}
                                <Badge className="absolute bottom-1.5 left-1.5 bg-white/85 px-2 text-[10px] tracking-normal text-ink shadow-sm backdrop-blur">
                                  {MEDIA_LABEL[creativeMediaKind(c)] || tm.label}
                                </Badge>
                              </div>
                            </div>
                          </div>
                        )
                      })}
                    </div>
                  )}
                </div>
              )
            })
          )}
        </div>

        {/* per-channel routing preview: what actually goes where */}
        {selectedCreatives.length > 0 && (
          <div className="space-y-1.5 rounded-xl border border-border bg-surface-muted/50 p-3.5">
            <div className="flex items-center gap-1.5 text-xs font-semibold text-ink-secondary">
              <Radio size={13} className="text-ink-muted" /> O que vai para cada canal
            </div>
            {routing.map(({ channel, posts: chPosts }) => (
              <div key={channel} className="flex items-center gap-2 text-xs">
                <ChannelIcons channels={[channel]} />
                <span className="font-semibold text-ink-secondary">{channelMeta(channel).label}</span>
                {chPosts.length === 0 ? (
                  <span className="text-danger">nenhum criativo compatível</span>
                ) : (
                  <span className="text-ink-muted">
                    {chPosts.map((p) => `${MEDIA_LABEL[creativeMediaKind(p.creative)] || 'post'}${p.cover ? ' + capa' : ''}`).join(', ')}
                  </span>
                )}
              </div>
            ))}
          </div>
        )}

        {/* per-channel caption: the exact text that goes out on each network */}
        {channels.length > 0 && (
          <div className="space-y-3">
            <Label className="flex items-center gap-1.5">
              <MessageSquareText size={13} style={{ color }} /> Legenda por canal
            </Label>
            {channels.map((channel) => {
              const expanded = !!expandedCaptions[channel]
              return (
                <div key={channel} className="flex flex-col gap-1.5">
                  <div className="flex items-center justify-between gap-1.5">
                    <div className="flex items-center gap-1.5 text-xs font-semibold text-ink-secondary">
                      <ChannelIcons channels={[channel]} /> {channelMeta(channel).label}
                    </div>
                    <button
                      type="button"
                      onClick={() => toggleCaption(channel)}
                      className="inline-flex items-center gap-1 rounded-lg px-1.5 py-0.5 text-[11px] font-semibold text-ink-muted transition hover:text-brand"
                    >
                      {expanded ? <ChevronUp size={13} /> : <ChevronDown size={13} />}
                      {expanded ? 'Recolher' : 'Expandir'}
                    </button>
                  </div>
                  <Textarea
                    rows={expanded ? 8 : 3}
                    maxRows={expanded ? 100 : 6}
                    value={captionByChannel[channel] ?? baseCaption}
                    placeholder="Legenda deste post…"
                    onChange={(e) => setChannelCaption(channel, e.target.value)}
                    onBlur={saveChannelCaption}
                  />
                </div>
              )
            })}
          </div>
        )}

        {/* 2 — when */}
        <div className="space-y-2">
          <Label className="flex items-center gap-1.5"><Clock size={13} style={{ color }} /> Quando publicar</Label>
          <div className="flex flex-wrap gap-2">
            {[{ v: 'immediate', label: 'Imediato', icon: Zap }, { v: 'scheduled', label: 'Agendar', icon: Clock }].map((o) => {
              const active = mode === o.v
              const Icon = o.icon
              return (
                <button
                  key={o.v}
                  type="button"
                  onClick={() => setMode(o.v)}
                  aria-pressed={active}
                  className={cn(
                    'inline-flex items-center gap-1.5 rounded-xl border px-3.5 py-2 text-sm font-semibold transition-all',
                    active ? 'border-transparent text-white shadow-sm' : 'border-border bg-surface text-ink-secondary hover:border-brand/40',
                  )}
                  style={active ? { background: color } : undefined}
                >
                  <Icon size={14} /> {o.label}
                </button>
              )
            })}
          </div>
          {mode === 'scheduled' && (
            <DateTimePicker value={scheduledAt} onChange={(v) => { setScheduledAt(v); saveField('scheduled_at', v) }} />
          )}
        </div>

        {/* 3 — optional extras */}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div className="flex flex-col gap-1.5 sm:col-span-2">
            <Label className="flex items-center gap-1.5"><MessageCircle size={13} style={{ color }} /> Primeiro comentário</Label>
            <Textarea
              rows={2}
              value={firstComment}
              placeholder="Comentário fixado no post…"
              onChange={(e) => setFirstComment(e.target.value)}
              onBlur={() => saveField('first_comment', firstComment)}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label className="flex items-center gap-1.5"><Link2 size={13} style={{ color }} /> Link na bio</Label>
            <Input
              value={linkInBio}
              placeholder="https://…"
              onChange={(e) => setLinkInBio(e.target.value)}
              onBlur={() => saveField('link_in_bio', linkInBio)}
            />
          </div>
        </div>

        {/* publish action */}
        <div className="flex items-center justify-between gap-3 border-t border-border pt-4">
          <p className="text-xs text-ink-muted">O ticket vai para “No ar” quando a publicação for concluída.</p>
          <Button onClick={handlePublish} disabled={!canPublish}>
            {publishing ? <Spinner size={14} className="border-white/30 border-t-white" /> : mode === 'immediate' ? <Zap size={14} /> : <Clock size={14} />}
            {mode === 'immediate' ? 'Publicar agora' : 'Agendar publicação'}
          </Button>
        </div>

        {/* live post statuses */}
        {posts.length > 0 && (
          <div className="space-y-2 border-t border-border pt-4">
            {posts.map((post) => {
              const st = POST_STATUS[post.status] || POST_STATUS.scheduled
              const StIcon = st.icon
              return (
                <div key={post.id} className="flex items-start justify-between gap-2 rounded-xl border border-border bg-surface px-3.5 py-2.5 sm:items-center">
                  {/* Mobile stacks network + date on the left and badge + action on
                      the right; from sm up it's the original single row. */}
                  <div className="flex min-w-0 flex-col gap-0.5 sm:flex-row sm:items-center sm:gap-2">
                    <div className="flex min-w-0 items-center gap-2">
                      <ChannelIcons channels={[post.provider]} />
                      <span className="truncate text-sm font-semibold text-ink">{channelMeta(post.provider).label}</span>
                    </div>
                    {post.scheduled_at && post.status === 'scheduled' && (
                      <span className="text-xs text-ink-muted"><span className="hidden sm:inline">· </span>{dt(post.scheduled_at)}</span>
                    )}
                  </div>
                  <div className="flex shrink-0 flex-col items-end gap-1.5 sm:flex-row sm:items-center sm:gap-2">
                    <Badge variant={st.variant}>
                      <StIcon size={11} className={cn('mr-0.5', post.status === 'publishing' && 'animate-spin')} />
                      {st.label}
                    </Badge>
                    {/* A not-yet-live publication can be CANCELED (the post is
                        removed before going live; schedule again anytime). */}
                    {['scheduled', 'failed'].includes(post.status) && onCancelPost && (
                      <Button
                        variant="outline"
                        size="sm"
                        className="h-7 px-2 text-xs text-danger hover:border-danger/40 hover:bg-danger/5"
                        onClick={() => onCancelPost(post.id)}
                        disabled={cancelingId === post.id}
                      >
                        {cancelingId === post.id ? <Spinner size={11} /> : <CalendarX2 size={11} />}
                        Cancelar
                      </Button>
                    )}
                    {post.status === 'published' && onUnpublish && (
                      <Button
                        variant="outline"
                        size="sm"
                        className="h-7 px-2 text-xs text-danger hover:border-danger/40 hover:bg-danger/5"
                        onClick={() => onUnpublish(post.id)}
                        disabled={unpublishingId === post.id}
                      >
                        {unpublishingId === post.id ? <Spinner size={11} /> : <Ban size={11} />}
                        Despublicar
                      </Button>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </div>
      </AiRewritingOverlay>

      <Suspense fallback={null}>
        <MediaViewer
          attachments={viewer.attachments}
          index={0}
          open={viewer.open}
          onClose={() => setViewer((v) => ({ ...v, open: false }))}
        />
      </Suspense>
    </Card>
  )
}
