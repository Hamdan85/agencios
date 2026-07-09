import { useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { Lock, ArrowRight } from 'lucide-react'
import { toast } from 'sonner'
import AuthShell from './AuthShell'
import { useResetPassword } from '@/hooks/useAuth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

// Landing page for the reset link mailed to the user (/redefinir-senha/:token).
// Public — the user is signed out. On success, sends them to /login to sign in
// with the new password.
export default function ResetPassword() {
  const { token } = useParams()
  const navigate = useNavigate()
  const reset = useResetPassword()
  const [form, setForm] = useState({ password: '', confirm: '' })
  const [error, setError] = useState(null)
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value })

  const submit = (e) => {
    e.preventDefault()
    setError(null)
    if (form.password !== form.confirm) {
      setError('As senhas não coincidem.')
      return
    }
    reset.mutate({ token, password: form.password }, {
      onSuccess: () => {
        toast.success('Senha redefinida. Faça login com a nova senha.')
        navigate('/login')
      },
      onError: (err) => setError(err.error || 'Link inválido ou expirado.'),
    })
  }

  return (
    <AuthShell
      title="Crie uma nova senha"
      subtitle="Escolha uma senha para voltar a acessar sua conta."
      footer={<Link to="/login" className="font-bold text-brand hover:underline">Voltar ao login</Link>}
    >
      <form onSubmit={submit} className="space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="password">Nova senha</Label>
          <div className="relative">
            <Lock size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
            <Input id="password" type="password" autoFocus required minLength={6} value={form.password} onChange={set('password')} className="pl-9" placeholder="mínimo 6 caracteres" />
          </div>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="confirm">Confirmar senha</Label>
          <div className="relative">
            <Lock size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
            <Input id="confirm" type="password" required minLength={6} value={form.confirm} onChange={set('confirm')} className="pl-9" placeholder="repita a senha" />
          </div>
        </div>
        {error && <p className="rounded-lg bg-danger/10 px-3 py-2 text-sm font-medium text-danger">{error}</p>}
        <Button type="submit" size="lg" className="w-full" disabled={reset.isPending}>
          {reset.isPending ? 'Salvando…' : <>Redefinir senha <ArrowRight size={18} /></>}
        </Button>
      </form>
    </AuthShell>
  )
}
