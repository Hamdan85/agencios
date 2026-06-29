import { useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { Mail, Lock, ArrowRight } from 'lucide-react'
import AuthShell from './AuthShell'
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
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const login = useLogin()
  const [form, setForm] = useState({ email: '', password: '' })
  const [error, setError] = useState(null)
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
      onError: (err) => setError(err.error || 'Não foi possível entrar.'),
    })
  }

  return (
    <AuthShell
      title="Bem-vindo de volta"
      subtitle="Entre para acessar o painel da sua agência."
      footer={<>Ainda não tem conta? <Link to="/cadastro" className="font-bold text-brand hover:underline">Criar conta</Link></>}
    >
      <form onSubmit={submit} className="space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="email">E-mail</Label>
          <div className="relative">
            <Mail size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
            <Input id="email" type="email" autoFocus required value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} className="pl-9" placeholder="voce@agencia.com" />
          </div>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="password">Senha</Label>
          <div className="relative">
            <Lock size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
            <Input id="password" type="password" required value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} className="pl-9" placeholder="••••••••" />
          </div>
        </div>
        {error && <p className="rounded-lg bg-danger/10 px-3 py-2 text-sm font-medium text-danger">{error}</p>}
        <Button type="submit" size="lg" className="w-full" disabled={login.isPending}>
          {login.isPending ? 'Entrando…' : <>Entrar <ArrowRight size={18} /></>}
        </Button>
      </form>
    </AuthShell>
  )
}
