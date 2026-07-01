import { useEffect, useMemo, useState } from 'react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { Spinner, EmptyState } from '@/components/ui/feedback'
import { DateTimePicker } from '@/components/ui/date-picker'
import { ChannelIcons } from '@/components/ui/iconography'
import { creativeMeta, channelMeta, channelsForCreative, creativeMediaKind } from '@/lib/constants'
import { dt } from '@/lib/formatters'
import { cn } from '@/lib/utils'
import {
  Send, Clock, Zap, MessageCircle, Link2, CheckCircle2, AlertCircle, Loader2, ImagePlus, Radio,
} from 'lucide-react'

const MEDIA_LABEL = { image: 'imagem', carousel: 'carrossel', video: 'vídeo', text: 'texto' }

const POST_STATUS = {
  scheduled:  { label: 'Agendado',   variant: 'muted',   icon: Clock },
  publishing: { label: 'Publicando…', variant: 'warning', icon: Loader2 },
  published:  { label: 'No ar',      variant: 'success', icon: CheckCircle2 },
  failed:     { label: 'Falhou',     variant: 'danger',  icon: AlertCircle },
}

// The "Postagem" step: pick ONE creative, choose immediate vs scheduled, and
// publish. The ticket only reaches "No ar" when a post actually succeeds.
export default function PostingPanel({ ticket, creatives = [], posts = [], onSave, onPublish, publishing = false, color = '#EC4899' }) {
  const fields = ticket?.fields?.scheduled || {}
  const channels = Array.isArray(ticket?.channels) ? ticket.channels : []
  const ready = creatives.filter((c) => c?.status === 'ready' && (c?.asset_urls?.length || 0) > 0)

  const [creativeId, setCreativeId] = useState('')
  const [mode, setMode] = useState(fields.post_mode || 'immediate')
  const [scheduledAt, setScheduledAt] = useState(fields.scheduled_at ? String(fields.scheduled_at).slice(0, 16) : '')
  const [firstComment, setFirstComment] = useState(fields.first_comment || '')
  const [linkInBio, setLinkInBio] = useState(fields.link_in_bio || '')

  // Default the selection to the saved one, else the only ready creative.
  useEffect(() => {
    const saved = fields.creative_id ? String(fields.creative_id) : ''
    if (saved && ready.some((c) => String(c.id) === saved)) setCreativeId(saved)
    else if (ready.length === 1) setCreativeId(String(ready[0].id))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ticket?.id, ready.length])

  const selected = ready.find((c) => String(c.id) === String(creativeId))
  const supported = useMemo(() => (selected ? channelsForCreative(selected, channels) : []), [selected, channels])
  const skipped = channels.filter((ch) => !supported.includes(ch))

  const saveField = (key, value) => onSave?.({ [key]: value })

  const canPublish = !!selected && supported.length > 0 && (mode === 'immediate' || !!scheduledAt) && !publishing

  const handlePublish = () => {
    if (!canPublish) return
    onPublish?.({
      creative_id: selected.id,
      mode,
      scheduled_at: mode === 'scheduled' ? scheduledAt : undefined,
    })
  }

  return (
    <Card className="overflow-hidden animate-rise">
      <div className="flex items-center gap-2.5 border-b border-border p-5" style={{ background: `${color}0A` }}>
        <div className="flex size-9 items-center justify-center rounded-xl" style={{ background: `${color}1A`, color }}>
          <Send size={18} strokeWidth={2.3} />
        </div>
        <div>
          <h3 className="font-display text-base font-bold text-ink">Postagem</h3>
          <p className="text-xs text-ink-muted">Escolha o criativo e publique — agora ou agendado.</p>
        </div>
      </div>

      <div className="space-y-5 p-5">
        {/* 1 — choose the creative */}
        <div className="space-y-2">
          <Label className="flex items-center gap-1.5"><ImagePlus size={13} style={{ color }} /> Criativo a postar</Label>
          {ready.length === 0 ? (
            <EmptyState
              icon={ImagePlus}
              title="Nenhum criativo pronto"
              description="Volte à Produção e gere ou anexe um criativo antes de postar."
              color={color}
            />
          ) : (
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              {ready.map((c) => {
                const m = creativeMeta(c.creative_type)
                const active = String(c.id) === String(creativeId)
                const thumb = c.asset_urls?.[0]
                return (
                  <button
                    key={c.id}
                    type="button"
                    onClick={() => setCreativeId(String(c.id))}
                    aria-pressed={active}
                    className={cn(
                      'group relative overflow-hidden rounded-xl border-2 text-left transition-all',
                      active ? 'border-brand ring-2 ring-brand/20' : 'border-border hover:border-brand/40',
                    )}
                  >
                    <div className="relative w-full" style={{ paddingBottom: '100%' }}>
                      <div className="absolute inset-0 overflow-hidden" style={{ background: `${m.color}10` }}>
                        {thumb ? (
                          <img src={thumb} alt={m.label} className="size-full object-cover" />
                        ) : (
                          <div className="flex size-full items-center justify-center"><m.icon size={24} style={{ color: m.color }} /></div>
                        )}
                        {active && (
                          <div className="absolute right-1.5 top-1.5 grid size-5 place-items-center rounded-full bg-brand text-white shadow">
                            <CheckCircle2 size={13} />
                          </div>
                        )}
                        <span className="absolute bottom-1.5 left-1.5 rounded-full bg-white/85 px-2 py-0.5 text-[10px] font-bold text-ink shadow-sm backdrop-blur">
                          {MEDIA_LABEL[creativeMediaKind(c)] || m.label}
                        </span>
                      </div>
                    </div>
                  </button>
                )
              })}
            </div>
          )}
        </div>

        {/* channel support for the selected creative */}
        {selected && (
          <div className="flex flex-wrap items-center gap-2 rounded-xl border border-border bg-surface-muted/50 px-3.5 py-2.5">
            <Radio size={14} className="text-ink-muted" />
            {supported.length > 0 ? (
              <>
                <span className="text-xs font-semibold text-ink-secondary">Vai ao ar em:</span>
                <ChannelIcons channels={supported} />
              </>
            ) : (
              <span className="text-xs font-semibold text-danger">Nenhum canal selecionado suporta {MEDIA_LABEL[creativeMediaKind(selected)]}.</span>
            )}
            {skipped.length > 0 && supported.length > 0 && (
              <span className="ml-auto text-[11px] text-ink-faint">Ignorados (sem suporte): {skipped.map((c) => channelMeta(c).label).join(', ')}</span>
            )}
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
                <div key={post.id} className="flex items-center justify-between gap-2 rounded-xl border border-border bg-surface px-3.5 py-2.5">
                  <div className="flex items-center gap-2">
                    <ChannelIcons channels={[post.provider]} />
                    <span className="text-sm font-semibold text-ink">{channelMeta(post.provider).label}</span>
                    {post.scheduled_at && post.status === 'scheduled' && (
                      <span className="text-xs text-ink-muted">· {dt(post.scheduled_at)}</span>
                    )}
                  </div>
                  <Badge variant={st.variant}>
                    <StIcon size={11} className={cn('mr-0.5', post.status === 'publishing' && 'animate-spin')} />
                    {st.label}
                  </Badge>
                </div>
              )
            })}
          </div>
        )}
      </div>
    </Card>
  )
}
