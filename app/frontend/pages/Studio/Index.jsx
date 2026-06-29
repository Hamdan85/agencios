import { useState } from 'react'
import {
  Sparkles, GalleryHorizontalEnd, Video, Image as ImageIcon,
  Wand2, Zap, Layers, CheckCircle2, Clock, Loader2, XCircle, BadgeDollarSign, Gauge,
} from 'lucide-react'
import { useStudio, useGenerations, useGenerate } from '@/hooks/useData'
import { useCurrentUser } from '@/hooks/useAuth'
import { useGenerationsChannel } from '@/hooks/useRealtime'
import { PageHeader } from '@/components/ui/page-header'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { Badge } from '@/components/ui/badge'
import { Page } from '@/components/ui/page'
import { ChannelIcons } from '@/components/ui/iconography'
import { cn } from '@/lib/utils'
import { brl, relativeDay } from '@/lib/formatters'
import { CREATIVE_TYPE_META, GENERATION_KIND_META, creativeMeta } from '@/lib/constants'
import { GeneratorCard } from '@/components/studio/GeneratorCard'
import { GenerateDialog } from '@/components/studio/GenerateDialog'

const HERO = '#F43F5E'

const GENERATORS = [
  { kind: 'carousel', icon: GalleryHorizontalEnd, title: 'Carrossel', subtitle: 'Padrão viral · copy + slides', color: '#7C3AED' },
  { kind: 'video', icon: Video, title: 'Vídeo UGC', subtitle: 'Avatar + voz a partir do roteiro', color: '#F43F5E' },
  { kind: 'image', icon: ImageIcon, title: 'Imagem', subtitle: 'Imagem original via prompt', color: '#0EA5E9' },
]

const STATUS_META = {
  queued: { label: 'Na fila', variant: 'muted', icon: Clock },
  processing: { label: 'Processando', variant: 'warning', icon: Loader2 },
  completed: { label: 'Concluído', variant: 'success', icon: CheckCircle2 },
  failed: { label: 'Falhou', variant: 'danger', icon: XCircle },
}

export default function StudioIndex() {
  const { data: studio, isLoading } = useStudio()
  const { data: live } = useGenerations()
  const { data: me } = useCurrentUser()
  const workspaceId = me?.workspace?.id
  useGenerationsChannel(workspaceId)

  const [dialogKind, setDialogKind] = useState(null)
  // The shared generation mutation is owned here and handed to the dialog.
  const generate = useGenerate()

  if (isLoading) return <PageLoader />

  const clients = studio?.clients || []
  const creativeTypes = studio?.creative_types || []
  const recent = live || studio?.recent_generations || []

  return (
    <Page className="animate-rise">
      <PageHeader
        eyebrow="Criação"
        title="Estúdio"
        icon={Sparkles}
        color={HERO}
        description="Gere criativos com IA — carrosséis, vídeos UGC e imagens, no padrão da marca do cliente."
      />

      {/* Generator cards */}
      <section className="mt-6">
        <SectionTitle icon={Wand2} color={HERO}>Gerar criativo</SectionTitle>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {GENERATORS.map((g) => (
            <GeneratorCard
              key={g.kind}
              icon={g.icon}
              title={g.title}
              subtitle={g.subtitle}
              color={g.color}
              onClick={() => setDialogKind(g.kind)}
            />
          ))}
        </div>
      </section>

      {/* Creative types gallery */}
      <section className="mt-9">
        <SectionTitle icon={Layers} color="#7C3AED">Tipos de criativo</SectionTitle>
        {creativeTypes.length === 0 ? (
          <EmptyState icon={Layers} color="#7C3AED" title="Nenhum tipo configurado" description="Os tipos de criativo aparecerão aqui." />
        ) : (
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            {creativeTypes.map((spec) => <SpecCard key={spec.type_key} spec={spec} />)}
          </div>
        )}
      </section>

      {/* Recent generations */}
      <section className="mt-9">
        <SectionTitle icon={Zap} color="#F59E0B">Gerações recentes</SectionTitle>
        {recent.length === 0 ? (
          <EmptyState
            icon={Sparkles}
            color={HERO}
            title="Nada gerado ainda"
            description="Use os geradores acima para criar seu primeiro criativo com IA."
          />
        ) : (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {recent.map((gen) => <GenerationCard key={gen.id} gen={gen} />)}
          </div>
        )}
      </section>

      <GenerateDialog
        kind={dialogKind}
        open={!!dialogKind}
        onOpenChange={(o) => !o && setDialogKind(null)}
        generate={generate}
        clients={clients}
      />
    </Page>
  )
}

// ── Creative type spec card ────────────────────────────────────────
function SpecCard({ spec }) {
  const meta = CREATIVE_TYPE_META[spec.type_key] || creativeMeta(spec.type_key)
  const Icon = meta.icon
  const fit = spec.network_fit || []
  const dims = spec.width && spec.height ? `${spec.width}×${spec.height}` : '—'

  return (
    <div className="group relative flex flex-col overflow-hidden rounded-2xl border border-border bg-surface p-4 lift">
      <span className="absolute inset-x-0 top-0 h-1" style={{ background: meta.color }} />
      <div className="flex items-start justify-between gap-2">
        <div className="grid size-11 place-items-center rounded-2xl" style={{ background: `${meta.color}14`, color: meta.color }}>
          <Icon size={22} strokeWidth={2.2} />
        </div>
        {spec.generatable && (
          <span className="inline-flex items-center gap-1 rounded-full bg-emerald/12 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-emerald">
            <Sparkles size={10} strokeWidth={2.6} /> Gerável
          </span>
        )}
      </div>

      <h4 className="mt-3 font-display text-base font-bold text-ink">{spec.label || meta.label}</h4>

      <div className="mt-1.5 flex flex-wrap items-center gap-2 text-[11px] font-semibold text-ink-muted">
        <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted px-2 py-0.5 font-mono tabular-nums">
          {dims}
        </span>
        {spec.aspect && (
          <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted px-2 py-0.5">{spec.aspect}</span>
        )}
      </div>

      {fit.length > 0 && (
        <div className="mt-3 border-t border-border pt-3">
          <p className="mb-1.5 text-[10px] font-bold uppercase tracking-wider text-ink-faint">Redes</p>
          <ChannelIcons channels={fit} size={13} max={6} />
        </div>
      )}
    </div>
  )
}

// ── Generation card ────────────────────────────────────────────────
function GenerationCard({ gen }) {
  const kindMeta = GENERATION_KIND_META[gen.kind] || GENERATION_KIND_META.image
  const KindIcon = kindMeta.icon
  const st = STATUS_META[gen.status] || STATUS_META.queued
  const StIcon = st.icon
  const when = relativeDay(gen.created_at)
  const billable = Number(gen.cost_cents) > 0

  return (
    <div className="relative flex items-center gap-3 overflow-hidden rounded-2xl border border-border bg-surface p-3.5 lift">
      <span className="absolute inset-y-0 left-0 w-1" style={{ background: kindMeta.color }} />
      <div
        className="grid size-12 shrink-0 place-items-center rounded-2xl text-white shadow-sm"
        style={{ background: `linear-gradient(135deg, ${kindMeta.color}, ${kindMeta.color}cc)` }}
      >
        <KindIcon size={22} strokeWidth={2.2} />
      </div>

      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <p className="truncate font-display text-sm font-bold text-ink">{kindMeta.label}</p>
          {gen.provider && (
            <span className="truncate text-[11px] font-medium text-ink-faint">· {gen.provider}</span>
          )}
        </div>
        <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
          <Badge variant={st.variant} className="gap-1">
            <StIcon size={11} strokeWidth={2.6} className={cn(gen.status === 'processing' && 'animate-spin')} />
            {st.label}
          </Badge>
          {billable && (
            <span className="inline-flex items-center gap-1 rounded-full bg-amber/15 px-2 py-0.5 text-[11px] font-bold text-[#B45309]">
              <BadgeDollarSign size={11} strokeWidth={2.6} /> {brl(gen.cost_cents)}
            </span>
          )}
          {gen.metered && (
            <span className="inline-flex items-center gap-1 rounded-full bg-brand-soft px-2 py-0.5 text-[11px] font-bold text-brand">
              <Gauge size={11} strokeWidth={2.6} /> medido
            </span>
          )}
        </div>
      </div>

      {when && (
        <span className="shrink-0 self-start text-[11px] font-semibold text-ink-faint">{when.text}</span>
      )}
    </div>
  )
}

// ── Section title ──────────────────────────────────────────────────
function SectionTitle({ icon: Icon, color, children }) {
  return (
    <div className="mb-4 flex items-center gap-2.5">
      <div className="grid size-8 place-items-center rounded-xl" style={{ background: `${color}16`, color }}>
        <Icon size={16} strokeWidth={2.4} />
      </div>
      <h2 className="font-display text-lg font-extrabold tracking-tight text-ink">{children}</h2>
    </div>
  )
}
