import { useTranslation } from 'react-i18next'
import { FileBarChart } from 'lucide-react'
import { usePortalReport } from '@/hooks/useData'
import { portalApi } from '@/api'
import { InlineSpinner, EmptyState } from '@/components/ui/feedback'
import ReportDeck from '@/components/report/ReportDeck'
import ReportToolbar from '@/components/report/ReportToolbar'

// The finalized campaign report for the client. Renders the same deck the agency
// sees (shared ReportDeck), with honest generating / absent states, plus the
// export/print toolbar (branded PDF download + print).
export default function PortalReportTab({ token, projectId, accent = '#7C3AED' }) {
  const { t } = useTranslation('portal')
  const { data, isLoading } = usePortalReport(token, projectId)

  if (isLoading) {
    return <div className="flex justify-center py-16"><InlineSpinner size={24} style={{ color: accent }} /></div>
  }

  if (data?.status === 'generating') {
    return (
      <div className="flex flex-col items-center gap-3 rounded-2xl border border-border bg-surface p-12 text-center">
        <InlineSpinner size={28} style={{ color: accent }} />
        <h2 className="font-display text-lg font-bold text-ink">{t('report.generatingTitle')}</h2>
        <p className="text-sm text-ink-muted">{t('report.generatingBody')}</p>
      </div>
    )
  }

  if (!data?.report) {
    return <EmptyState icon={FileBarChart} title={t('report.notAvailableTitle')}
      description={t('report.notAvailableBody')} />
  }

  return (
    <div>
      <div className="mb-4 flex justify-end">
        <ReportToolbar
          pdfUrl={portalApi.reportPdfUrl(token, projectId)}
          filename={t('report.filename', { name: data.report.project_name || t('report.filenameFallback') })}
          accent={accent}
        />
      </div>
      <ReportDeck report={data.report} />
    </div>
  )
}
