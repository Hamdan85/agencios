import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Mail, ArrowRight, MailCheck } from 'lucide-react'
import AuthShell from './AuthShell'
import { useForgotPassword } from '@/hooks/useAuth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

export default function ForgotPassword() {
  const forgot = useForgotPassword()
  const [email, setEmail] = useState('')
  const [error, setError] = useState(null)
  const [sent, setSent] = useState(false)

  const submit = (e) => {
    e.preventDefault()
    setError(null)
    forgot.mutate(email, {
      onSuccess: () => setSent(true),
      onError: (err) => setError(err.error || 'Não foi possível enviar o link.'),
    })
  }

  if (sent) {
    return (
      <AuthShell
        title="Verifique seu e-mail"
        subtitle="Se houver uma conta com esse endereço, enviamos um link para redefinir a senha."
        footer={<Link to="/login" className="font-bold text-brand hover:underline">Voltar ao login</Link>}
      >
        <div className="flex flex-col items-center gap-4 py-4 text-center">
          <MailCheck size={40} className="text-emerald" />
          <p className="text-sm text-ink-muted">O link expira em 20 minutos. Não recebeu? Verifique a caixa de spam.</p>
        </div>
      </AuthShell>
    )
  }

  return (
    <AuthShell
      title="Esqueceu a senha?"
      subtitle="Informe seu e-mail e enviaremos um link para criar uma nova senha."
      footer={<>Lembrou a senha? <Link to="/login" className="font-bold text-brand hover:underline">Entrar</Link></>}
    >
      <form onSubmit={submit} className="space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="email">E-mail</Label>
          <div className="relative">
            <Mail size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
            <Input id="email" type="email" autoFocus required value={email} onChange={(e) => setEmail(e.target.value)} className="pl-9" placeholder="voce@agencia.com" />
          </div>
        </div>
        {error && <p className="rounded-lg bg-danger/10 px-3 py-2 text-sm font-medium text-danger">{error}</p>}
        <Button type="submit" size="lg" className="w-full" disabled={forgot.isPending}>
          {forgot.isPending ? 'Enviando…' : <>Enviar link <ArrowRight size={18} /></>}
        </Button>
      </form>
    </AuthShell>
  )
}
