import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import {
  ArrowLeft, Mail, Phone, FileText, FolderKanban, Receipt, Wallet,
  Building2, StickyNote, Pencil, Plus, ListChecks, Sparkles,
} from 'lucide-react'
import { useClient, useClientMutations } from '@/hooks/useData'
import { PageLoader, EmptyState } from '@/components/ui/feedback'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Avatar } from '@/components/ui/avatar'
import { Card } from '@/components/ui/card'
import { StatCard } from '@/components/ui/page-header'
import PositioningEditDialog from '@/components/client/PositioningEditDialog'
import { POSITIONING_FIELDS } from '@/lib/constants'
import { brl, date } from '@/lib/formatters'
import { cn } from '@/lib/utils'

// Read view of the client's brand positioning.
function PositioningSection({ client, onEdit }) {
  const positioning = client.positioning || {}
  const has = client.has_positioning
  const filled = POSITIONING_FIELDS.filter((f) => {
    const v = positioning[f.key]
    return Array.isArray(v) ? v.length > 0 : !!v
  })

  return (
    <section className="mb-8">
      <div className="mb-3 flex items-center gap-2">
        <Sparkles size={18} className="text-indigo" />
        <h2 className="font-display text-lg font-bold text-ink">Posicionamento</h2>
        {has && (
          <Button variant="ghost" size="sm" className="ml-auto text-ink-muted" onClick={onEdit}>
            <Pencil size={14} /> Editar
          </Button>
        )}
      </div>

      {!has ? (
        <EmptyState
          icon={Sparkles}
          color="#6366F1"
          title="Sem posicionamento"
          description="Defina o posicionamento de marca deste cliente — vira contexto da IA em todos os tickets dos seus projetos."
          action={<Button onClick={onEdit}><Sparkles size={16} /> Definir posicionamento</Button>}
        />
      ) : (
        <Card className="space-y-5 p-6">
          {positioning.statement && (
            <p className="border-l-2 border-indigo pl-4 text-[15px] font-medium leading-relaxed text-ink-secondary">
              {positioning.statement}
            </p>
          )}
          <div className="grid grid-cols-1 gap-x-8 gap-y-4 sm:grid-cols-2">
            {filled.map((f) => {
              const v = positioning[f.key]
              return (
                <div key={f.key}>
                  <p className="text-xs font-bold uppercase tracking-wider text-ink-faint">{f.label}</p>
                  {f.type === 'pillars' ? (
                    <div className="mt-1.5 flex flex-wrap gap-1.5">
                      {v.map((p, i) => (
                        <span key={i} className="rounded-full px-2.5 py-1 text-xs font-semibold" style={{ background: '#6366F114', color: '#6366F1' }}>{p}</span>
                      ))}
                    </div>
                  ) : (
                    <p className="mt-1 text-sm text-ink-secondary">{v}</p>
                  )}
                </div>
              )
            })}
          </div>
        </Card>
      )}
    </section>
  )
}

const PROJECT_STATUS = {
  active: { label: 'Ativo', variant: 'success' },
  paused: { label: 'Pausado', variant: 'warning' },
  archived: { label: 'Arquivado', variant: 'muted' },
}
const INVOICE_STATUS = {
  draft: { label: 'Rascunho', variant: 'muted' },
  open: { label: 'Em aberto', variant: 'default' },
  paid: { label: 'Pago', variant: 'success' },
  overdue: { label: 'Vencida', variant: 'danger' },
  canceled: { label: 'Cancelada', variant: 'muted' },
}

function ContactChip({ icon: Icon, value, mono }) {
  if (!value) return null
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full bg-surface-muted px-3 py-1.5 text-sm font-medium text-ink-secondary">
      <Icon size={14} className="text-brand" />
      <span className={cn(mono && 'font-mono text-xs')}>{value}</span>
    </span>
  )
}

export default function ClientShow() {
  const { id } = useParams()
  const { data, isLoading } = useClient(id)
  const { synthesize, updatePositioning } = useClientMutations()
  const [positioningOpen, setPositioningOpen] = useState(false)

  if (isLoading) return <PageLoader />

  const client = data?.client || {}
  const projects = data?.projects || []
  const invoices = data?.invoices || []
  const archived = client.status === 'archived'

  const totalPaid = invoices
    .filter((i) => i.status === 'paid')
    .reduce((sum, i) => sum + (Number(i.amount_cents) || 0), 0)

  return (
    <div>
      <Link to="/clientes" className="mb-5 inline-flex items-center gap-1.5 text-sm font-semibold text-ink-muted transition hover:text-brand">
        <ArrowLeft size={16} /> Clientes
      </Link>

      {/* Hero header */}
      <Card className="mb-6 overflow-hidden">
        <div className="h-2 w-full bg-brand-gradient" />
        <div className="flex flex-wrap items-start justify-between gap-4 p-6">
          <div className="flex items-start gap-4">
            <Avatar name={client.name} size={72} ring />
            <div>
              <div className="flex items-center gap-2">
                <h1 className="font-display text-2xl font-extrabold tracking-tight text-ink">{client.name || 'Cliente'}</h1>
                <Badge variant={archived ? 'muted' : 'success'}>{archived ? 'Arquivado' : 'Ativo'}</Badge>
              </div>
              {client.company && (
                <p className="mt-0.5 flex items-center gap-1.5 text-sm font-medium text-ink-muted">
                  <Building2 size={14} /> {client.company}
                </p>
              )}
              <div className="mt-3 flex flex-wrap gap-2">
                <ContactChip icon={Mail} value={client.email} />
                <ContactChip icon={Phone} value={client.phone} />
                <ContactChip icon={FileText} value={client.document} mono />
              </div>
            </div>
          </div>
          <Button asChild variant="outline">
            <Link to="/clientes"><Pencil size={16} /> Editar</Link>
          </Button>
        </div>
        {client.notes && (
          <div className="border-t border-border bg-surface-muted/50 px-6 py-4">
            <p className="flex items-start gap-2 text-sm text-ink-secondary">
              <StickyNote size={15} className="mt-0.5 shrink-0 text-amber" /> {client.notes}
            </p>
          </div>
        )}
      </Card>

      {/* Stat row */}
      <div className="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
        <StatCard label="Projetos" value={projects.length} icon={FolderKanban} color="#10B981" sub="vinculados ao cliente" />
        <StatCard label="Faturas" value={invoices.length} icon={Receipt} color="#F97316" sub="emitidas" />
        <StatCard label="Total faturado" value={brl(totalPaid)} icon={Wallet} color="#7C3AED" sub="cobranças pagas" />
      </div>

      {/* Positioning */}
      <PositioningSection client={client} onEdit={() => setPositioningOpen(true)} />

      {/* Projects */}
      <section className="mb-8">
        <div className="mb-3 flex items-center gap-2">
          <FolderKanban size={18} className="text-emerald" />
          <h2 className="font-display text-lg font-bold text-ink">Projetos</h2>
          <span className="rounded-full bg-emerald/12 px-2 py-0.5 text-xs font-bold text-emerald">{projects.length}</span>
        </div>
        {projects.length === 0 ? (
          <EmptyState
            icon={FolderKanban}
            color="#10B981"
            title="Nenhum projeto"
            description="Este cliente ainda não tem projetos."
            action={<Button asChild variant="outline"><Link to="/projetos"><Plus size={16} /> Novo projeto</Link></Button>}
          />
        ) : (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {projects.map((p) => {
              const color = p.color || '#7C3AED'
              const st = PROJECT_STATUS[p.status] || PROJECT_STATUS.active
              return (
                <Link
                  key={p.id}
                  to={`/projetos/${p.id}`}
                  className="group relative flex flex-col overflow-hidden rounded-2xl border border-border bg-surface lift"
                >
                  <div className="h-1.5 w-full" style={{ background: color }} />
                  <div className="flex flex-1 flex-col p-4">
                    <div className="flex items-start justify-between gap-2">
                      <h3 className="font-display text-base font-bold text-ink">{p.name}</h3>
                      <Badge variant={st.variant}>{st.label}</Badge>
                    </div>
                    <span className="mt-3 inline-flex w-fit items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-bold" style={{ background: `${color}14`, color }}>
                      <ListChecks size={13} /> {p.tickets_count ?? 0} tickets
                    </span>
                  </div>
                </Link>
              )
            })}
          </div>
        )}
      </section>

      {/* Invoices */}
      <section>
        <div className="mb-3 flex items-center gap-2">
          <Receipt size={18} className="text-orange" />
          <h2 className="font-display text-lg font-bold text-ink">Faturas</h2>
          <span className="rounded-full bg-orange/12 px-2 py-0.5 text-xs font-bold text-orange">{invoices.length}</span>
        </div>
        {invoices.length === 0 ? (
          <EmptyState
            icon={Receipt}
            color="#F97316"
            title="Nenhuma fatura"
            description="Nenhuma cobrança foi emitida para este cliente."
            action={<Button asChild variant="outline"><Link to="/cobrancas"><Plus size={16} /> Nova cobrança</Link></Button>}
          />
        ) : (
          <Card className="divide-y divide-border">
            {invoices.map((inv) => {
              const st = INVOICE_STATUS[inv.status] || INVOICE_STATUS.draft
              return (
                <div key={inv.id} className="flex items-center justify-between gap-4 p-4">
                  <div className="flex items-center gap-3">
                    <div className="flex size-10 items-center justify-center rounded-xl bg-orange/12 text-orange">
                      <Receipt size={18} />
                    </div>
                    <div>
                      <p className="font-display text-base font-bold text-ink">{brl(inv.amount_cents)}</p>
                      {inv.description && <p className="text-xs text-ink-muted">{inv.description}</p>}
                    </div>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="text-xs font-medium text-ink-muted">Venc. {date(inv.due_date)}</span>
                    <Badge variant={st.variant}>{st.label}</Badge>
                  </div>
                </div>
              )
            })}
          </Card>
        )}
      </section>

      <PositioningEditDialog
        open={positioningOpen}
        onOpenChange={setPositioningOpen}
        client={client}
        mutations={{ synthesize, updatePositioning }}
      />
    </div>
  )
}
