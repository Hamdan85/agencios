import { Link, useParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import {
  ArrowLeft, FileBarChart, AlertTriangle, Send, MailCheck,
} from 'lucide-react'
import { useReport, useSendReport } from '@/hooks/useData'
import { useCurrentUser } from '@/hooks/useAuth'
import { canManage } from '@/lib/roles'
import { Page } from '@/components/ui/page'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { InlineSpinner as Spinner } from '@/components/ui/feedback'
import { PageLoader, EmptyState, InlineSpinner } from '@/components/ui/feedback'
import { dt } from '@/lib/formatters'
import { reportsApi } from '@/api'
import ReportDeck from '@/components/report/ReportDeck'
import ReportToolbar from '@/components/report/ReportToolbar'

export default function ReportShow() {
  const { t } = useTranslation('reports')
  const { id } = useParams()
  const { data: report, isLoading } = useReport(id)

  if (isLoading) return <PageLoader />
  if (!report) return <Page><EmptyState icon={FileBarChart} title={t('show.notFound')} /></Page>

  const back = report.project_id ? `/campanhas/${report.project_id}` : '/campanhas'

  if (report.status === 'generating') {
    return (
      <Page>
        <BackLink to={back} />
        <Card className="flex flex-col items-center gap-3 p-12 text-center">
          <InlineSpinner size={32} className="text-brand" />
          <h1 className="font-display text-xl font-bold text-ink">{t('show.generatingTitle')}</h1>
          <p className="text-sm text-ink-secondary">{t('show.generatingDescription')}</p>
        </Card>
      </Page>
    )
  }

  if (report.status === 'failed') {
    return (
      <Page>
        <BackLink to={back} />
        <EmptyState icon={AlertTriangle} color="#EF4444" title={t('show.failedTitle')} description={t('show.failedDescription')} />
      </Page>
    )
  }

  return (
    <Page>
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <BackLink to={back} />
        <div className="flex flex-wrap items-center gap-3">
          <ReportToolbar pdfUrl={reportsApi.pdfUrl(report.id)} filename={t('show.pdfFilename', { name: report.project_name || t('show.pdfFallbackName') })} />
          <SendToClientButton report={report} />
        </div>
      </div>

      <ReportDeck report={report} />
    </Page>
  )
}

function BackLink({ to }) {
  const { t } = useTranslation('reports')
  return (
    <Link to={to} className="inline-flex items-center gap-1.5 text-sm font-semibold text-ink-muted transition hover:text-brand">
      <ArrowLeft size={16} /> {t('show.back')}
    </Link>
  )
}

// Manager-only "Enviar ao cliente": e-mails the branded PDF to the client. Hidden
// until the deck is ready; disabled (with a hint) when the client has no e-mail.
// Once sent, shows when it went out and offers a resend.
function SendToClientButton({ report }) {
  const { t } = useTranslation('reports')
  const me = useCurrentUser()
  const send = useSendReport(report.id)
  if (report.status !== 'ready' || !canManage(me?.membership?.role)) return null

  const sent = report.sent_to_client_at
  const noEmail = !report.client_email

  return (
    <div className="flex items-center gap-3">
      {sent && (
        <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-emerald">
          <MailCheck size={14} /> {t('send.sentAt', { date: dt(sent) })}
        </span>
      )}
      <Button
        variant={sent ? 'outline' : 'default'}
        size="sm"
        disabled={send.isPending || noEmail}
        title={noEmail ? t('send.noEmail') : undefined}
        onClick={() => send.mutate()}
      >
        {send.isPending ? <Spinner size={15} /> : <Send size={15} />}
        {sent ? t('send.resend') : t('send.send')}
      </Button>
    </div>
  )
}
