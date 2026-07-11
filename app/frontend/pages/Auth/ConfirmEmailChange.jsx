import { useEffect, useRef, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { CheckCircle2, XCircle } from 'lucide-react'
import AuthShell from './AuthShell'
import { InlineSpinner } from '@/components/ui/feedback'
import { accountApi } from '@/api'

// Landing page for the link mailed to a user's NEW address. It confirms the
// pending e-mail change (public — the user may be signed out) and reports the
// result. Runs the confirmation exactly once.
export default function ConfirmEmailChange() {
  const { t } = useTranslation('auth')
  const { token } = useParams()
  const [state, setState] = useState('loading') // loading | ok | error
  const [message, setMessage] = useState('')
  const ran = useRef(false)

  useEffect(() => {
    if (ran.current) return
    ran.current = true
    accountApi.confirmEmailChange(token)
      .then((res) => { setState('ok'); setMessage(res?.email ? t('confirmEmail.updatedTo', { email: res.email }) : t('confirmEmail.updated')) })
      .catch((err) => { setState('error'); setMessage(err?.error || t('confirmEmail.invalidLink')) })
  }, [token, t])

  const copy = {
    loading: { title: t('confirmEmail.loading.title'), subtitle: t('confirmEmail.loading.subtitle') },
    ok: { title: t('confirmEmail.ok.title'), subtitle: t('confirmEmail.ok.subtitle') },
    error: { title: t('confirmEmail.error.title'), subtitle: t('confirmEmail.error.subtitle') },
  }[state]

  return (
    <AuthShell
      title={copy.title}
      subtitle={copy.subtitle}
      footer={<Link to="/conta" className="font-bold text-brand hover:underline">{t('confirmEmail.goToAccount')}</Link>}
    >
      <div className="flex flex-col items-center gap-4 py-4 text-center">
        {state === 'loading' && <InlineSpinner size={40} className="text-brand" />}
        {state === 'ok' && <CheckCircle2 size={40} className="text-emerald" />}
        {state === 'error' && <XCircle size={40} className="text-danger" />}
        {message && <p className="text-sm text-ink-muted">{message}</p>}
        {state !== 'loading' && (
          <Link to="/login" className="text-sm font-semibold text-brand hover:underline">{t('confirmEmail.backToLogin')}</Link>
        )}
      </div>
    </AuthShell>
  )
}
