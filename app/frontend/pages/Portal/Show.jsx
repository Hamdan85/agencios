import { useMemo } from 'react'
import { useParams, useSearchParams } from 'react-router-dom'
import { usePortal } from '@/hooks/useData'
import { InlineSpinner } from '@/components/ui/feedback'
import PortalShell from '@/components/portal/PortalShell'
import CampaignList from '@/components/portal/CampaignList'
import CampaignDetail from '@/components/portal/CampaignDetail'

// The login-less client central. The path token (Client#approval_token) is the
// credential — the same link the client already receives. Landing lists every
// campaign; `?campanha=<id>&aba=<tab>` opens one campaign's status-driven views.
export default function PortalShow() {
  const { token } = useParams()
  const [params, setParams] = useSearchParams()
  const { data, isLoading, isError } = usePortal(token)

  const campaigns = data?.campaigns || []
  const agency = data?.agency || {}
  const accent = agency.primary_color || '#7C3AED'

  const campaignId = params.get('campanha')
  const activeTab = params.get('aba')
  const current = useMemo(
    () => campaigns.find((c) => String(c.id) === String(campaignId)),
    [campaigns, campaignId],
  )

  const openCampaign = (c) => setParams({ campanha: String(c.id), aba: (c.available_tabs || ['quadro'])[0] }, { replace: false })
  const setTab = (tab) => setParams((prev) => { const sp = new URLSearchParams(prev); sp.set('aba', tab); return sp }, { replace: true })
  const backToList = () => setParams({}, { replace: false })

  if (isLoading) {
    return (
      <PortalShell agency={agency}>
        <div className="flex justify-center py-24"><InlineSpinner size={28} style={{ color: accent }} /></div>
      </PortalShell>
    )
  }

  if (isError || !data) {
    return (
      <PortalShell agency={agency}>
        <div className="py-24 text-center text-ink-muted">
          Este link não é mais válido. Fale com sua agência para receber um novo.
        </div>
      </PortalShell>
    )
  }

  return (
    <PortalShell
      agency={agency}
      subtitle={current ? current.name : `Central de ${data.client?.name || 'cliente'}`}
    >
      {current
        ? <CampaignDetail campaign={current} token={token} activeTab={activeTab} onTab={setTab} accent={accent} onBack={backToList} />
        : <CampaignList campaigns={campaigns} onOpen={openCampaign} accent={accent} />}
    </PortalShell>
  )
}
