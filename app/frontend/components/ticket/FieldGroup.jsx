import { useEffect, useMemo, useState } from 'react'
import { statusMeta, CREATIVE_TYPE_META, CHANNEL_META, creativeTypesForChannels } from '@/lib/constants'
import { Card } from '@/components/ui/card'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Switch } from '@/components/ui/switch'
import { Spinner } from '@/components/ui/feedback'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { ChipsInput } from '@/components/ui/chips-input'
import { DatePicker, DateTimePicker } from '@/components/ui/date-picker'
import { ChannelIcons } from '@/components/ui/iconography'
import DoneSummary from './DoneSummary'
import { dt } from '@/lib/formatters'
import { cn } from '@/lib/utils'
import {
  Lightbulb, Ruler, Wand2, CalendarClock, Radio, LineChart, CheckCircle2,
  Check, Link2, Target, Users, Layers, FlaskConical, Hash, ListChecks, Clock,
  MessageSquareText, ShieldCheck, FileText, ThumbsUp, AlertTriangle, Repeat,
  Eye, Heart, MessageCircle, Share2, Bookmark, BarChart3, ExternalLink, Save,
  Ban,
} from 'lucide-react'

// ── Per-status field schema ──────────────────────────────────────────────
// Field kinds: text | textarea | lines (one-per-line ⇄ array) | date | datetime
//              | select | channels | switch
const SCHEMAS = {
  ideation: {
    icon: Lightbulb,
    title: 'Brief & Ideação',
    helper: 'O coração da ideia: para quem, por quê e em que formato.',
    fields: [
      { key: 'brief', label: 'Brief', kind: 'textarea', rows: 5, icon: FileText, placeholder: 'Descreva o contexto, a mensagem e o tom desejado…', full: true },
      { key: 'objective', label: 'Objetivo', kind: 'text', icon: Target, placeholder: 'Ex.: gerar awareness do lançamento' },
      { key: 'target_persona', label: 'Persona-alvo', kind: 'text', icon: Users, placeholder: 'Quem queremos impactar?' },
      { key: 'content_pillar', label: 'Pilar de conteúdo', kind: 'text', icon: Layers, placeholder: 'Ex.: bastidores, educacional…' },
      { key: 'format_hypothesis', label: 'Hipótese de formato', kind: 'text', icon: FlaskConical, placeholder: 'Ex.: Reel narrativo de 30s' },
      { key: 'references', label: 'Referências', kind: 'lines', icon: Link2, placeholder: 'Uma URL por linha…', full: true, hint: 'Uma referência por linha' },
    ],
  },
  scoping: {
    icon: Ruler,
    title: 'Escopo & Entregáveis',
    helper: 'Defina o tipo de criativo, os canais e o que será entregue.',
    fields: [
      { key: 'channels', label: 'Canais', kind: 'channels', icon: Radio, full: true, hint: 'Onde este conteúdo vai ao ar' },
      { key: 'creative_types', label: 'Tipos de criativo', kind: 'creativeTypes', icon: Wand2, full: true, hint: 'Habilitados pelos canais escolhidos — os demais ficam desativados' },
      { key: 'copy_brief', label: 'Briefing de copy', kind: 'textarea', rows: 3, icon: MessageSquareText, placeholder: 'Direção de mensagem para a legenda…', full: true },
      { key: 'script', label: 'Roteiro', kind: 'textarea', rows: 4, icon: FileText, placeholder: 'Roteiro / storyboard…', full: true },
      { key: 'deliverables', label: 'Entregáveis', kind: 'lines', icon: ListChecks, placeholder: 'Um entregável por linha…', full: true, hint: 'Pelo menos um entregável (um por linha). Na postagem você escolhe qual vai ao ar.' },
      { key: 'due_date', label: 'Prazo', kind: 'date', icon: CalendarClock },
      { key: 'effort_estimate', label: 'Estimativa de esforço', kind: 'text', icon: Clock, placeholder: 'Ex.: 4h, 2 dias…' },
    ],
  },
  production: {
    icon: Wand2,
    title: 'Produção & Legenda',
    helper: 'A copy final, hashtags e o status de aprovação do cliente.',
    fields: [
      { key: 'caption', label: 'Legenda', kind: 'textarea', rows: 5, icon: MessageSquareText, placeholder: 'Escreva ou gere a legenda final…', full: true },
      { key: 'hashtags', label: 'Hashtags', kind: 'chips', icon: Hash, placeholder: 'Digite e tecle Enter…', full: true, hint: 'Enter ou vírgula adiciona; clique no × para remover' },
      { key: 'approval_status', label: 'Aprovação', kind: 'select', icon: ShieldCheck, options: 'approval' },
      { key: 'internal_notes', label: 'Notas internas', kind: 'textarea', rich: true, rows: 3, icon: FileText, placeholder: 'Observações para a equipe…', full: true },
    ],
  },
  scheduled: {
    icon: CalendarClock,
    title: 'Postagem',
    helper: 'Escolha o criativo e publique — imediatamente ou agendado.',
    fields: [
      { key: 'scheduled_at', label: 'Publicar em', kind: 'datetime', icon: CalendarClock, full: true },
      { key: 'first_comment', label: 'Primeiro comentário', kind: 'textarea', rows: 2, icon: MessageCircle, placeholder: 'Comentário fixado no post…', full: true },
      { key: 'link_in_bio', label: 'Link na bio', kind: 'text', icon: Link2, placeholder: 'https://…' },
      { key: 'auto_publish', label: 'Publicação automática', kind: 'switch', icon: Radio, hint: 'Publicar sem revisão manual' },
    ],
  },
  retrospective: {
    icon: LineChart,
    title: 'Retrospectiva',
    helper: 'O que funcionou, o que melhorar e a recomendação para o futuro.',
    fields: [
      { key: 'wins', label: 'Vitórias', kind: 'lines', icon: ThumbsUp, placeholder: 'O que deu certo? Uma por linha…', full: true, hint: 'Uma por linha' },
      { key: 'improvements', label: 'Melhorias', kind: 'lines', icon: AlertTriangle, placeholder: 'O que pode melhorar? Uma por linha…', full: true, hint: 'Uma por linha' },
      { key: 'repeat_recommendation', label: 'Recomendação', kind: 'radio', icon: Repeat, options: 'repeat' },
      { key: 'lessons_learned', label: 'Lições aprendidas', kind: 'textarea', rich: true, rows: 4, icon: FileText, placeholder: 'O aprendizado consolidado…', full: true },
    ],
  },
}

const APPROVAL_OPTIONS = [
  { value: 'pending', label: 'Pendente' },
  { value: 'approved', label: 'Aprovado' },
  { value: 'changes_requested', label: 'Ajustes solicitados' },
]
const REPEAT_OPTIONS = [
  { value: 'repeat', label: 'Repetir' },
  { value: 'iterate', label: 'Iterar' },
  { value: 'retire', label: 'Aposentar' },
]

const METRIC_TILES = [
  { key: 'reach', label: 'Alcance', icon: Eye, color: '#0EA5E9' },
  { key: 'views', label: 'Views', icon: BarChart3, color: '#7C3AED' },
  { key: 'likes', label: 'Curtidas', icon: Heart, color: '#EC4899' },
  { key: 'comments', label: 'Comentários', icon: MessageCircle, color: '#F59E0B' },
  { key: 'shares', label: 'Compart.', icon: Share2, color: '#10B981' },
  { key: 'saves', label: 'Salvos', icon: Bookmark, color: '#6366F1' },
]

const linesToArray = (str) => String(str || '').split('\n').map((s) => s.trim()).filter(Boolean)
const arrayToLines = (arr) => (Array.isArray(arr) ? arr.join('\n') : arr || '')

// ── Read-only stat tiles for a post's metrics ────────────────────────────
function MetricTiles({ metrics }) {
  return (
    <div className="grid grid-cols-3 gap-2 sm:grid-cols-6">
      {METRIC_TILES.map((t) => {
        const Icon = t.icon
        const value = metrics?.[t.key]
        return (
          <div key={t.key} className="rounded-xl border border-border bg-surface-muted/60 p-2.5 text-center">
            <Icon size={15} strokeWidth={2.3} className="mx-auto" style={{ color: t.color }} />
            <p className="mt-1 font-display text-base font-extrabold text-ink">
              {value != null ? Number(value).toLocaleString('pt-BR') : '—'}
            </p>
            <p className="text-[10px] font-semibold uppercase tracking-wide text-ink-muted">{t.label}</p>
          </div>
        )
      })}
    </div>
  )
}

// ── Read-only view for published / done ──────────────────────────────────
function PublishedView({ status, posts, color, onUnpublish, unpublishingId }) {
  const Icon = status === 'done' ? CheckCircle2 : Radio
  return (
    <Card className="overflow-hidden animate-rise">
      <div className="flex items-center gap-2.5 border-b border-border p-5" style={{ background: `${color}08` }}>
        <div className="flex size-9 items-center justify-center rounded-xl" style={{ background: `${color}18`, color }}>
          <Icon size={18} strokeWidth={2.3} />
        </div>
        <div>
          <h3 className="font-display text-base font-bold text-ink">
            {status === 'done' ? 'Métricas finais' : 'No ar — monitorando'}
          </h3>
          <p className="text-xs text-ink-muted">Desempenho por publicação.</p>
        </div>
      </div>
      <div className="space-y-3 p-5">
        {(posts || []).length === 0 ? (
          <p className="rounded-xl border border-dashed border-border bg-surface-muted/40 px-4 py-6 text-center text-sm text-ink-muted">
            Nenhuma publicação registrada ainda.
          </p>
        ) : (
          posts.map((post) => {
            const unpublished = post.status === 'unpublished'
            return (
              <div key={post.id} className={cn('rounded-xl border border-border bg-surface p-4', unpublished && 'opacity-60')}>
                <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <ChannelIcons channels={post.provider ? [post.provider] : []} size={14} />
                    <span className="text-sm font-semibold text-ink">{post.username || post.provider || 'Publicação'}</span>
                    <span className="text-xs text-ink-muted">· {dt(post.published_at || post.scheduled_at)}</span>
                    {unpublished && <Badge variant="muted">Despublicado</Badge>}
                  </div>
                  <div className="flex items-center gap-2">
                    {post.permalink && (
                      <a
                        href={post.permalink}
                        target="_blank"
                        rel="noreferrer"
                        className="inline-flex items-center gap-1 text-xs font-bold text-brand hover:underline"
                      >
                        Ver post <ExternalLink size={12} />
                      </a>
                    )}
                    {status !== 'done' && post.status === 'published' && onUnpublish && (
                      <Button
                        variant="outline"
                        size="sm"
                        className="h-8 px-2.5 text-xs text-danger hover:border-danger/40 hover:bg-danger/5"
                        onClick={() => onUnpublish(post.id)}
                        disabled={unpublishingId === post.id}
                      >
                        {unpublishingId === post.id ? <Spinner size={12} /> : <Ban size={12} />}
                        Despublicar
                      </Button>
                    )}
                  </div>
                </div>
                {post.caption && <p className="mb-3 line-clamp-2 text-sm text-ink-secondary">{post.caption}</p>}
                {unpublished && post.failure_reason && (
                  <p className="mb-3 flex items-start gap-1.5 rounded-lg bg-warning/10 px-3 py-2 text-xs text-warning">
                    <AlertTriangle size={13} className="mt-0.5 shrink-0" /> {post.failure_reason}
                  </p>
                )}
                <MetricTiles metrics={post.metrics} />
              </div>
            )
          })
        )}
      </div>
    </Card>
  )
}

// ── The contextual editable field group ──────────────────────────────────
export default function FieldGroup({ ticket, posts, subtasks = [], onSave, saving = false }) {
  const status = ticket?.status
  const m = statusMeta(status)
  const schema = SCHEMAS[status]

  const serverValues = ticket?.fields?.[status] || {}

  // Local draft state — initialise from server, reset when ticket/status changes.
  const [draft, setDraft] = useState({})
  useEffect(() => {
    setDraft(serverValues)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ticket?.id, status, JSON.stringify(serverValues)])

  // Whether the local draft diverges from the persisted server values.
  // (Computed before any early return so hook order stays stable.)
  const dirty = useMemo(() => {
    if (!schema) return false
    return schema.fields.some((f) => {
      const a = draft[f.key]
      const b = serverValues[f.key]
      if (f.kind === 'lines') return arrayToLines(a) !== arrayToLines(b)
      if (f.kind === 'channels' || f.kind === 'chips' || f.kind === 'creativeTypes') return JSON.stringify(a || []) !== JSON.stringify(b || [])
      return (a ?? '') !== (b ?? '')
    })
  }, [draft, serverValues, schema])

  // Read-only stages render a different surface entirely.
  if (status === 'published') {
    return <PublishedView status={status} posts={posts} color={m.color} />
  }
  // "Concluído" gets a rich, graphic case-study summary of the whole ticket.
  if (status === 'done') {
    return <DoneSummary ticket={ticket} posts={posts} subtasks={subtasks} />
  }
  if (!schema) return null

  const setField = (key, value) => setDraft((d) => ({ ...d, [key]: value }))

  // Normalise line fields to arrays before persisting.
  const toPayload = (next) => {
    const payload = { ...next }
    schema.fields.forEach((f) => {
      if (f.kind === 'lines') payload[f.key] = linesToArray(next[f.key])
    })
    return payload
  }

  const handleSave = () => {
    if (!dirty || saving) return
    onSave?.(toPayload(draft))
  }

  // Set a field and persist immediately — used by selects, channels, switches
  // and date pickers (these have no blur event to hang a save on).
  const setAndPersist = (key, value) =>
    setDraft((d) => {
      const next = { ...d, [key]: value }
      onSave?.(toPayload(next))
      return next
    })

  // Toggle a channel and prune any scoped creative type the new channel set no
  // longer supports (a creative type is only valid while a chosen channel fits
  // it), persisting both in one write.
  const toggleChannel = (ch) =>
    setDraft((d) => {
      const list = Array.isArray(d.channels) ? d.channels : []
      const channels = list.includes(ch) ? list.filter((c) => c !== ch) : [...list, ch]
      const valid = creativeTypesForChannels(channels)
      const creative_types = (Array.isArray(d.creative_types) ? d.creative_types : []).filter((t) => valid.includes(t))
      const next = { ...d, channels, creative_types }
      onSave?.(toPayload(next))
      return next
    })

  const renderField = (f) => {
    const Icon = f.icon
    const value = draft[f.key]
    const labelEl = (
      <Label className="flex items-center gap-1.5">
        {Icon && <Icon size={13} style={{ color: m.color }} />}
        {f.label}
      </Label>
    )

    let control
    switch (f.kind) {
      case 'textarea':
        control = (
          <Textarea
            rich={f.rich}
            rows={f.rows}
            value={value || ''}
            placeholder={f.placeholder}
            onChange={(e) => setField(f.key, e.target.value)}
            onBlur={handleSave}
          />
        )
        break
      case 'chips':
        control = (
          <ChipsInput
            value={Array.isArray(value) ? value : []}
            onChange={(v) => setAndPersist(f.key, v)}
            placeholder={f.placeholder}
            prefix={f.key === 'hashtags' ? '#' : ''}
          />
        )
        break
      case 'radio': {
        const opts =
          f.options === 'approval' ? APPROVAL_OPTIONS :
          f.options === 'repeat' ? REPEAT_OPTIONS : []
        control = (
          <div className="flex flex-wrap gap-2">
            {opts.map((o) => {
              const active = value === o.value
              return (
                <button
                  key={o.value}
                  type="button"
                  onClick={() => setAndPersist(f.key, o.value)}
                  aria-pressed={active}
                  className={cn(
                    'inline-flex items-center gap-1.5 rounded-xl border px-3.5 py-2 text-sm font-semibold transition-all',
                    active
                      ? 'border-transparent text-white shadow-sm'
                      : 'border-border bg-surface text-ink-secondary hover:border-brand/40',
                  )}
                  style={active ? { background: m.color } : undefined}
                >
                  <span className={cn('grid size-4 place-items-center rounded-full border-2', active ? 'border-white' : 'border-ink-faint')}>
                    {active && <span className="size-1.5 rounded-full bg-white" />}
                  </span>
                  {o.label}
                </button>
              )
            })}
          </div>
        )
        break
      }
      case 'lines':
        control = (
          <Textarea
            rows={f.rows || 3}
            value={arrayToLines(value)}
            placeholder={f.placeholder}
            className="font-mono text-[13px]"
            onChange={(e) => setField(f.key, e.target.value)}
            onBlur={handleSave}
          />
        )
        break
      case 'date':
        control = (
          <DatePicker
            value={value ? String(value).slice(0, 10) : ''}
            onChange={(v) => setAndPersist(f.key, v)}
          />
        )
        break
      case 'datetime':
        control = (
          <DateTimePicker
            value={value ? String(value).slice(0, 16) : ''}
            onChange={(v) => setAndPersist(f.key, v)}
          />
        )
        break
      case 'select': {
        const opts = f.options === 'approval' ? APPROVAL_OPTIONS : REPEAT_OPTIONS
        control = (
          <Select value={value || ''} onValueChange={(v) => setAndPersist(f.key, v)}>
            <SelectTrigger>
              <SelectValue placeholder="Selecione…" />
            </SelectTrigger>
            <SelectContent>
              {opts.map((o) => (
                <SelectItem key={o.value} value={o.value}>
                  {o.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        )
        break
      }
      case 'channels': {
        const connected = ticket?.connected_channels || []
        const clientId = ticket?.project?.client_id
        control = (
          <div className="flex flex-wrap gap-2">
            {Object.entries(CHANNEL_META).map(([ch, meta]) => {
              const Ch = meta.icon
              const active = Array.isArray(value) && value.includes(ch)
              const isConnected = connected.includes(ch)

              // Not connected for this client → render disabled; clicking opens
              // the client's integrations (Configurações tab) in a new tab.
              if (!isConnected) {
                const inner = (
                  <>
                    <Ch size={14} strokeWidth={2.3} />
                    {meta.label}
                    <ExternalLink size={12} className="opacity-70" />
                  </>
                )
                const cls = cn(
                  'inline-flex items-center gap-1.5 rounded-xl border border-dashed px-3 py-1.5 text-sm font-semibold text-ink-faint transition-all',
                  active ? 'border-amber/60 ring-1 ring-amber/40' : 'border-border',
                  clientId ? 'hover:border-brand/40 hover:text-ink-secondary' : 'cursor-not-allowed opacity-60',
                )
                return clientId ? (
                  <a
                    key={ch}
                    href={`/clientes/${clientId}/configuracoes`}
                    target="_blank"
                    rel="noreferrer"
                    title={`${meta.label} não está conectado neste cliente — clique para conectar`}
                    className={cls}
                  >
                    {inner}
                  </a>
                ) : (
                  <span key={ch} className={cls} title={`${meta.label} não está conectado`}>{inner}</span>
                )
              }

              return (
                <button
                  key={ch}
                  type="button"
                  onClick={() => toggleChannel(ch)}
                  className={cn(
                    'inline-flex items-center gap-1.5 rounded-xl border px-3 py-1.5 text-sm font-semibold transition-all',
                    active ? 'border-transparent text-white shadow-sm' : 'border-border bg-surface text-ink-secondary hover:border-brand/40',
                  )}
                  style={active ? { background: meta.color } : undefined}
                >
                  <Ch size={14} strokeWidth={2.3} />
                  {meta.label}
                </button>
              )
            })}
          </div>
        )
        break
      }
      case 'creativeTypes': {
        const chosenChannels = Array.isArray(draft.channels) ? draft.channels : []
        const valid = creativeTypesForChannels(chosenChannels)
        const noChannels = chosenChannels.length === 0
        const selected = Array.isArray(value) ? value : []
        control = (
          <div className="flex flex-wrap gap-2">
            {Object.entries(CREATIVE_TYPE_META).map(([key, meta]) => {
              const Ct = meta.icon
              const active = selected.includes(key)
              // Enabled only when a chosen channel supports the type. With no
              // channel picked yet everything is disabled — choose channels first.
              const enabled = !noChannels && valid.includes(key)

              if (!enabled && !active) {
                return (
                  <span
                    key={key}
                    title={noChannels ? 'Escolha os canais primeiro' : 'Indisponível para os canais escolhidos'}
                    className="inline-flex cursor-not-allowed items-center gap-1.5 rounded-xl border border-dashed border-border px-3 py-1.5 text-sm font-semibold text-ink-faint opacity-60"
                  >
                    <Ct size={14} strokeWidth={2.3} />
                    {meta.label}
                  </span>
                )
              }

              return (
                <button
                  key={key}
                  type="button"
                  onClick={() => setAndPersist(f.key, active ? selected.filter((t) => t !== key) : [...selected, key])}
                  aria-pressed={active}
                  className={cn(
                    'inline-flex items-center gap-1.5 rounded-xl border px-3 py-1.5 text-sm font-semibold transition-all',
                    active ? 'border-transparent text-white shadow-sm' : 'border-border bg-surface text-ink-secondary hover:border-brand/40',
                  )}
                  style={active ? { background: meta.color } : undefined}
                >
                  <Ct size={14} strokeWidth={2.3} />
                  {meta.label}
                </button>
              )
            })}
          </div>
        )
        break
      }
      case 'switch':
        control = (
          <div className="flex items-center gap-3 rounded-xl border border-border bg-surface-muted/50 px-3.5 py-2.5">
            <Switch
              checked={!!value}
              onCheckedChange={(checked) => setAndPersist(f.key, checked)}
            />
            <span className="text-sm font-medium text-ink-secondary">{value ? 'Ativada' : 'Desativada'}</span>
          </div>
        )
        break
      default:
        control = (
          <Input
            value={value || ''}
            placeholder={f.placeholder}
            onChange={(e) => setField(f.key, e.target.value)}
            onBlur={handleSave}
          />
        )
    }

    return (
      <div key={f.key} className={cn('flex flex-col gap-1.5', f.full ? 'sm:col-span-2' : '')}>
        {labelEl}
        {control}
        {f.hint && <p className="text-[11px] text-ink-faint">{f.hint}</p>}
      </div>
    )
  }

  const Heading = schema.icon
  return (
    <Card className="overflow-hidden animate-rise">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border p-5" style={{ background: `${m.color}08` }}>
        <div className="flex items-center gap-2.5">
          <div className="flex size-9 items-center justify-center rounded-xl" style={{ background: `${m.color}18`, color: m.color }}>
            <Heading size={18} strokeWidth={2.3} />
          </div>
          <div>
            <h3 className="font-display text-base font-bold text-ink">{schema.title}</h3>
            <p className="text-xs text-ink-muted">{schema.helper}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {dirty && <span className="text-[11px] font-semibold text-amber">Alterações não salvas</span>}
          <Button size="sm" variant={dirty ? 'default' : 'outline'} onClick={handleSave} disabled={!dirty || saving}>
            {saving ? <Spinner size={14} className="border-white/30 border-t-white" /> : dirty ? <Save size={14} /> : <Check size={14} />}
            {dirty ? 'Salvar' : 'Salvo'}
          </Button>
        </div>
      </div>
      <div className="grid grid-cols-1 gap-4 p-5 sm:grid-cols-2">
        {schema.fields.map(renderField)}
      </div>
    </Card>
  )
}
