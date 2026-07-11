import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Button } from '@/components/ui/button'
import { ErrorScene } from '@/components/errors/ErrorScene'

export default function NotFound() {
  const { t } = useTranslation('errors')
  return (
    <ErrorScene
      code="404"
      title={t('notFound.title')}
      description={t('notFound.description')}
      actions={(
        <>
          <Button asChild size="lg"><Link to="/painel">{t('actions.backToDashboard')}</Link></Button>
          <Button variant="ghost" size="lg" onClick={() => window.history.back()}>{t('actions.back')}</Button>
        </>
      )}
    />
  )
}
