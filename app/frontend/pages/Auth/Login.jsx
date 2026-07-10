import { useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Mail, Lock, ArrowRight } from 'lucide-react'
import AuthShell from './AuthShell'
import GoogleAuth from './GoogleAuth'
import { useLogin } from '@/hooks/useAuth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

// Only allow same-origin OAuth consent redirects (Doorkeeper sends users here
// as /login?return_to=/oauth/authorize?...). Anything else is ignored to avoid
// an open redirect.
function safeReturnTo(value) {
  return value && value.startsWith('/oauth/authorize') ? value : null
}

export default function Login() {
  const { t } = useTranslation('auth')
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const login = useLogin()
  const [form, setForm] = useState({ email: '', password: '' })
  const [error, setError] = useState(() =>
    searchParams.get('error') === 'google' ? t('login.googleError') : null,
  )
  const returnTo = safeReturnTo(searchParams.get('return_to'))

  const submit = (e) => {
    e.preventDefault()
    setError(null)
    login.mutate(form, {
      onSuccess: () => {
        // The OAuth consent page is server-rendered (not a React route), so do a
        // full-page navigation back to it; otherwise go to the dashboard.
        if (returnTo) window.location.href = returnTo
        else navigate('/painel')
      },
      onError: (err) => setError(err.error || t('login.error')),
    })
  }

  return (
    <AuthShell
      title={t('login.title')}
      subtitle={t('login.subtitle')}
      footer={<>{t('login.noAccount')} <Link to="/cadastro" className="font-bold text-brand hover:underline">{t('login.signUpLink')}</Link></>}
    >
      <form onSubmit={submit} className="space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="email">{t('fields.email')}</Label>
          <div className="relative">
            <Mail size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
            <Input id="email" type="email" autoFocus required value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} className="pl-9" placeholder={t('fields.emailPlaceholder')} />
          </div>
        </div>
        <div className="space-y-1.5">
          <div className="flex items-center justify-between">
            <Label htmlFor="password">{t('fields.password')}</Label>
            <Link to="/recuperar-senha" className="text-xs font-semibold text-ink-muted hover:text-brand hover:underline">{t('login.forgotPassword')}</Link>
          </div>
          <div className="relative">
            <Lock size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
            <Input id="password" type="password" required value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} className="pl-9" placeholder="••••••••" />
          </div>
        </div>
        {error && <p className="rounded-lg bg-danger/10 px-3 py-2 text-sm font-medium text-danger">{error}</p>}
        <Button type="submit" size="lg" className="w-full" disabled={login.isPending}>
          {login.isPending ? t('login.submitting') : <>{t('login.submit')} <ArrowRight size={18} /></>}
        </Button>
        <GoogleAuth label={t('login.withGoogle')} returnTo={returnTo} />
      </form>
    </AuthShell>
  )
}
