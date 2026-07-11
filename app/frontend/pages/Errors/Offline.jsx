import { useTranslation } from 'react-i18next'
import { Button } from '@/components/ui/button'
import { ErrorScene } from '@/components/errors/ErrorScene'

export default function Offline() {
  const { t } = useTranslation('errors')
  return (
    <ErrorScene
      code="OFFLINE"
      title={t('offline.title')}
      description={t('offline.description')}
      actions={<Button size="lg" onClick={() => window.location.reload()}>{t('actions.reload')}</Button>}
    />
  )
}
