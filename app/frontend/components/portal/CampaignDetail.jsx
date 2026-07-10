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

// A centered, self-scrolling band for the non-board tabs (métricas, relatório).
// The board + approvals tabs fill and scroll themselves (board columns scroll
// internally; approvals is a board-style column), so the shell never page-scrolls.
function ScrollBand({ children }) {
  return (
    <div className="scrollbar-subtle min-h-0 flex-1 overflow-y-auto">
      <div className="mx-auto w-full max-w-6xl px-4 py-6 sm:px-6">{children}</div>
    </div>
  )
}

// One campaign's status-driven views. The header band (back + title + tabs) is
// fixed; the content band fills the remaining height. The server decides which
// tabs exist (`available_tabs`): active/paused → quadro + (aprovações) +
// métricas; completed/archived → quadro (all tickets) + relatório.
export default function CampaignDetail({ campaign, token, activeTab, onTab, accent = '#7C3AED', onBack }) {
  const tabs = campaign.available_tabs || ['quadro']
  const active = tabs.includes(activeTab) ? activeTab : tabs[0]
  const pending = campaign.counts?.pending_approval || 0

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      {/* Fixed header band */}
      <div className="shrink-0 border-b border-border/70 bg-canvas/60">
        <div className="mx-auto w-full max-w-6xl px-4 pt-4 sm:px-6">
          {onBack && (
            <button
              onClick={onBack}
              className="mb-3 inline-flex items-center gap-1.5 text-sm font-semibold text-ink-muted transition hover:text-ink"
            >
              <ArrowLeft size={16} /> Voltar às campanhas
            </button>
          )}
          <div className="flex items-center gap-2.5">
            <span className="size-3 rounded-full" style={{ background: campaign.color || accent }} />
            <h1 className="font-display text-xl font-extrabold tracking-tight text-ink sm:text-2xl">{campaign.name}</h1>
          </div>
          <p className="mt-1 text-sm text-ink-muted">{campaign.status_label}</p>

          {tabs.length > 1 && (
            <div className="mt-4 flex flex-wrap gap-1.5">
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
        </div>
      </div>

      {/* Content band — fills the rest; board/approvals self-scroll, the rest ride ScrollBand */}
      <div className="flex min-h-0 flex-1 flex-col">
        {active === 'quadro' && <PortalBoard token={token} projectId={campaign.id} accent={accent} />}
        {active === 'aprovacoes' && <PortalApprovals token={token} campaignId={campaign.id} accent={accent} />}
        {active === 'metricas' && (
          <ScrollBand><PortalMetrics token={token} projectId={campaign.id} accent={accent} /></ScrollBand>
        )}
        {active === 'relatorio' && (
          <ScrollBand><PortalReportTab token={token} projectId={campaign.id} accent={accent} /></ScrollBand>
        )}
      </div>
    </div>
  )
}
