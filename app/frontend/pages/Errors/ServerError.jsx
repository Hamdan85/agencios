import { useRouteError } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Button } from '@/components/ui/button'
import { ErrorScene } from '@/components/errors/ErrorScene'

// Rendered by React Router's errorElement whenever a route's render or loader
// throws. Reloading re-mounts the router from scratch, which clears most
// transient render-crash state.
export default function ServerError() {
  const { t } = useTranslation('errors')
  const error = useRouteError()
  if (import.meta.env.DEV && error) console.error(error)

  return (
    <ErrorScene
      code="500"
      title={t('serverError.title')}
      description={t('serverError.description')}
      actions={(
        <>
          <Button size="lg" onClick={() => window.location.reload()}>{t('actions.reload')}</Button>
          <Button variant="ghost" size="lg" onClick={() => { window.location.href = '/painel' }}>{t('actions.backToDashboard')}</Button>
        </>
      )}
    />
  )
}
