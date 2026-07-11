import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useTranslation, Trans } from 'react-i18next'
import { User, Mail, Lock, Building2, ArrowRight } from 'lucide-react'
import AuthShell from './AuthShell'
import GoogleAuth from './GoogleAuth'
import { useRegister } from '@/hooks/useAuth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

const Field = ({ icon: Icon, ...props }) => (
  <div className="relative">
    <Icon size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
    <Input {...props} className="pl-9" />
  </div>
)

export default function Register() {
  const { t } = useTranslation('auth')
  const navigate = useNavigate()
  const register = useRegister()
  const [form, setForm] = useState({ name: '', email: '', password: '', workspace_name: '' })
  const [error, setError] = useState(null)
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value })

  const submit = (e) => {
    e.preventDefault()
    setError(null)
    register.mutate(form, {
      onSuccess: () => navigate('/painel'),
      onError: (err) => setError(err.error || t('register.error')),
    })
  }

  return (
    <AuthShell
      title={t('register.title')}
      subtitle={t('register.subtitle')}
      footer={<>{t('register.hasAccount')} <Link to="/login" className="font-bold text-brand hover:underline">{t('register.loginLink')}</Link></>}
    >
      <form onSubmit={submit} className="space-y-4">
        <div className="space-y-1.5">
          <Label>{t('register.nameLabel')}</Label>
          <Field icon={User} required value={form.name} onChange={set('name')} placeholder={t('register.namePlaceholder')} autoFocus />
        </div>
        <div className="space-y-1.5">
          <Label>{t('register.agencyLabel')}</Label>
          <Field icon={Building2} value={form.workspace_name} onChange={set('workspace_name')} placeholder={t('register.agencyPlaceholder')} />
        </div>
        <div className="space-y-1.5">
          <Label>{t('fields.email')}</Label>
          <Field icon={Mail} type="email" required value={form.email} onChange={set('email')} placeholder={t('fields.emailPlaceholder')} />
        </div>
        <div className="space-y-1.5">
          <Label>{t('fields.password')}</Label>
          <Field icon={Lock} type="password" required minLength={6} value={form.password} onChange={set('password')} placeholder={t('fields.passwordPlaceholder')} />
        </div>
        {error && <p className="rounded-lg bg-danger/10 px-3 py-2 text-sm font-medium text-danger">{error}</p>}
        <Button type="submit" size="lg" className="w-full" disabled={register.isPending}>
          {register.isPending ? t('register.submitting') : <>{t('register.submit')} <ArrowRight size={18} /></>}
        </Button>
        <GoogleAuth label={t('register.withGoogle')} />
        <p className="text-center text-xs text-ink-faint">{t('register.trialNote')}</p>
        <p className="text-center text-xs text-ink-faint">
          <Trans
            t={t}
            i18nKey="register.terms"
            components={{
              termsLink: <a href="/termos" className="font-semibold text-ink-muted hover:text-brand hover:underline" />,
              privacyLink: <a href="/privacidade" className="font-semibold text-ink-muted hover:text-brand hover:underline" />,
            }}
          />
        </p>
      </form>
    </AuthShell>
  )
}
