import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
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
      onError: (err) => setError(err.error || 'Não foi possível criar a conta.'),
    })
  }

  return (
    <AuthShell
      title="Crie sua agência"
      subtitle="Em segundos você tem o quadro, o calendário e o estúdio prontos."
      footer={<>Já tem conta? <Link to="/login" className="font-bold text-brand hover:underline">Entrar</Link></>}
    >
      <form onSubmit={submit} className="space-y-4">
        <div className="space-y-1.5">
          <Label>Seu nome</Label>
          <Field icon={User} required value={form.name} onChange={set('name')} placeholder="Maria Silva" autoFocus />
        </div>
        <div className="space-y-1.5">
          <Label>Nome da agência</Label>
          <Field icon={Building2} value={form.workspace_name} onChange={set('workspace_name')} placeholder="Estúdio Criativo" />
        </div>
        <div className="space-y-1.5">
          <Label>E-mail</Label>
          <Field icon={Mail} type="email" required value={form.email} onChange={set('email')} placeholder="voce@agencia.com" />
        </div>
        <div className="space-y-1.5">
          <Label>Senha</Label>
          <Field icon={Lock} type="password" required minLength={6} value={form.password} onChange={set('password')} placeholder="mínimo 6 caracteres" />
        </div>
        {error && <p className="rounded-lg bg-danger/10 px-3 py-2 text-sm font-medium text-danger">{error}</p>}
        <Button type="submit" size="lg" className="w-full" disabled={register.isPending}>
          {register.isPending ? 'Criando…' : <>Criar conta <ArrowRight size={18} /></>}
        </Button>
        <GoogleAuth label="Criar conta com Google" />
        <p className="text-center text-xs text-ink-faint">14 dias de teste · sem cartão</p>
        <p className="text-center text-xs text-ink-faint">
          Ao criar conta, você concorda com os{' '}
          <a href="/termos" className="font-semibold text-ink-muted hover:text-brand hover:underline">Termos de Uso</a>{' '}
          e a{' '}
          <a href="/privacidade" className="font-semibold text-ink-muted hover:text-brand hover:underline">Política de Privacidade</a>.
        </p>
      </form>
    </AuthShell>
  )
}
