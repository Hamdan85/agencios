import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Mail, ArrowRight, MailCheck } from 'lucide-react'
import AuthShell from './AuthShell'
import { useForgotPassword } from '@/hooks/useAuth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

export default function ForgotPassword() {
  const { t } = useTranslation('auth')
  const forgot = useForgotPassword()
  const [email, setEmail] = useState('')
  const [error, setError] = useState(null)
  const [sent, setSent] = useState(false)

  const submit = (e) => {
    e.preventDefault()
    setError(null)
    forgot.mutate(email, {
      onSuccess: () => setSent(true),
      onError: (err) => setError(err.error || t('forgot.error')),
    })
  }

  if (sent) {
    return (
      <AuthShell
        title={t('forgot.sent.title')}
        subtitle={t('forgot.sent.subtitle')}
        footer={<Link to="/login" className="font-bold text-brand hover:underline">{t('forgot.sent.backToLogin')}</Link>}
      >
        <div className="flex flex-col items-center gap-4 py-4 text-center">
          <MailCheck size={40} className="text-emerald" />
          <p className="text-sm text-ink-muted">{t('forgot.sent.note')}</p>
        </div>
      </AuthShell>
    )
  }

  return (
    <AuthShell
      title={t('forgot.title')}
      subtitle={t('forgot.subtitle')}
      footer={<>{t('forgot.remembered')} <Link to="/login" className="font-bold text-brand hover:underline">{t('forgot.loginLink')}</Link></>}
    >
      <form onSubmit={submit} className="space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="email">{t('fields.email')}</Label>
          <div className="relative">
            <Mail size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
            <Input id="email" type="email" autoFocus required value={email} onChange={(e) => setEmail(e.target.value)} className="pl-9" placeholder={t('fields.emailPlaceholder')} />
          </div>
        </div>
        {error && <p className="rounded-lg bg-danger/10 px-3 py-2 text-sm font-medium text-danger">{error}</p>}
        <Button type="submit" size="lg" className="w-full" disabled={forgot.isPending}>
          {forgot.isPending ? t('forgot.submitting') : <>{t('forgot.submit')} <ArrowRight size={18} /></>}
        </Button>
      </form>
    </AuthShell>
  )
}
