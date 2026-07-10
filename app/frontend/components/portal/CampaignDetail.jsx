import { LayoutGrid, CheckSquare, BarChart3, FileBarChart, ArrowLeft } from 'lucide-react'
import PortalBoard from './PortalBoard'
import PortalApprovals from './PortalApprovals'
import PortalMetrics from './PortalMetrics'
import PortalReportTab from './PortalReportTab'

const TAB_META = {
  quadro: { label: 'Quadro', icon: LayoutGrid },
  aprovacoes: { label: 'Aprovações', icon: CheckSquare },
  metricas: { label: 'Métricas', icon: BarChart3 },
  relatorio: { label: 'Relatório', icon: FileBarChart },
}

// One campaign's status-driven views. The server decides which tabs exist
// (`available_tabs`): active/paused → quadro + (aprovações) + métricas;
// completed/archived → quadro (all tickets) + relatório.
export default function CampaignDetail({ campaign, token, activeTab, onTab, accent = '#7C3AED', onBack }) {
  const tabs = campaign.available_tabs || ['quadro']
  const active = tabs.includes(activeTab) ? activeTab : tabs[0]
  const pending = campaign.counts?.pending_approval || 0

  return (
    <div>
      {onBack && (
        <button
          onClick={onBack}
          className="mb-4 inline-flex items-center gap-1.5 text-sm font-semibold text-ink-muted transition hover:text-ink"
        >
          <ArrowLeft size={16} /> Voltar às campanhas
        </button>
      )}
      <div className="mb-1 flex items-center gap-2.5">
        <span className="size-3 rounded-full" style={{ background: campaign.color || accent }} />
        <h1 className="font-display text-2xl font-extrabold tracking-tight text-ink">{campaign.name}</h1>
      </div>
      <p className="mb-4 text-sm text-ink-muted">{campaign.status_label}</p>

      {tabs.length > 1 && (
        <div className="mb-5 flex flex-wrap gap-1.5 border-b border-border">
          {tabs.map((key) => {
            const meta = TAB_META[key]
            if (!meta) return null
            const Icon = meta.icon
            const on = key === active
            return (
              <button key={key} onClick={() => onTab(key)}
                className={`-mb-px flex items-center gap-1.5 border-b-2 px-3 py-2.5 text-sm font-semibold transition ${on ? '' : 'border-transparent text-ink-muted hover:text-ink'}`}
                style={on ? { borderColor: accent, color: accent } : undefined}>
                <Icon size={15} /> {meta.label}
                {key === 'aprovacoes' && pending > 0 && (
                  <span className="ml-0.5 rounded-full bg-amber/20 px-1.5 text-[11px] font-bold text-[#B45309]">{pending}</span>
                )}
              </button>
            )
          })}
        </div>
      )}

      {active === 'quadro' && <PortalBoard token={token} projectId={campaign.id} accent={accent} />}
      {active === 'aprovacoes' && <PortalApprovals token={token} campaignId={campaign.id} accent={accent} />}
      {active === 'metricas' && <PortalMetrics token={token} projectId={campaign.id} accent={accent} />}
      {active === 'relatorio' && <PortalReportTab token={token} projectId={campaign.id} accent={accent} />}
    </div>
  )
}
