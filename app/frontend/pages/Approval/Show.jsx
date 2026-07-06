import { useParams } from 'react-router-dom'
import { useState } from 'react'
import { CheckCircle2, MessageSquare, Loader2 } from 'lucide-react'
import { toast } from 'sonner'
import { useQueryClient } from '@tanstack/react-query'
import { usePublicApproval } from '@/hooks/useData'
import { approvalsApi } from '@/api'
import { keys } from '@/api/queryKeys'
import CreativeExperience from '@/components/creative/CreativeExperience'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { Button } from '@/components/ui/button'

export default function ApprovalShow() {
  const { token } = useParams()
  const { data, isLoading, isError } = usePublicApproval(token)
  const qc = useQueryClient()
  const confirm = useConfirm()
  const [busyId, setBusyId] = useState(null)

  if (isLoading) return <div className="flex min-h-screen items-center justify-center"><Loader2 className="animate-spin text-brand" /></div>
  if (isError || !data) return <div className="flex min-h-screen items-center justify-center p-6 text-center text-ink-muted">Link inválido ou expirado.</div>

  const brand = data.branding || {}
  const refresh = () => qc.invalidateQueries({ queryKey: keys.publicApproval(token) })

  const approve = async (c) => {
    const ok = await confirm({ title: 'Aprovar este criativo?', description: 'Confirma que este conteúdo está aprovado para publicação?', confirmLabel: 'Aprovar' })
    if (!ok) return
    setBusyId(c.id)
    try { await approvalsApi.approve(token, c.id); refresh(); toast.success('Criativo aprovado!') }
    catch (e) { toast.error(e?.error || 'Erro ao aprovar.') }
    finally { setBusyId(null) }
  }

  const requestChanges = async (c) => {
    const feedback = window.prompt('O que precisa ser ajustado?')
    if (feedback == null) return
    const ok = await confirm({ title: 'Pedir ajustes?', description: 'Enviaremos seu comentário para a equipe.', confirmLabel: 'Enviar' })
    if (!ok) return
    setBusyId(c.id)
    try { await approvalsApi.requestChanges(token, c.id, feedback); refresh(); toast.success('Ajustes solicitados!') }
    catch (e) { toast.error(e?.error || 'Erro ao enviar.') }
    finally { setBusyId(null) }
  }

  return (
    <div className="min-h-screen bg-surface-muted">
      <header className="px-6 py-5 text-white" style={{ background: brand.primary_color || '#7C3AED' }}>
        <div className="mx-auto flex max-w-3xl items-center gap-3">
          {brand.logo_url ? <img src={brand.logo_url} alt={brand.name} className="size-9 rounded-lg bg-white object-cover" />
            : <div className="flex size-9 items-center justify-center rounded-lg bg-white/20 font-bold">{brand.name?.[0]}</div>}
          <span className="font-display text-lg font-bold">{brand.name}</span>
        </div>
      </header>

      <main className="mx-auto max-w-3xl px-4 py-8">
        <h1 className="mb-1 font-display text-2xl font-bold text-ink">Aprovação de conteúdo</h1>
        <p className="mb-6 text-ink-muted">{data.campaign} · {data.title}</p>

        {data.approved && (
          <div className="mb-6 flex items-center gap-2 rounded-xl bg-emerald/10 px-4 py-3 text-emerald">
            <CheckCircle2 size={18} /> Tudo aprovado! A publicação será agendada automaticamente.
          </div>
        )}

        <div className="flex flex-col gap-8">
          {(data.creatives || []).map((c) => (
            <div key={c.id}>
              <CreativeExperience creative={c} />
              {c.caption && <p className="mt-3 whitespace-pre-wrap text-sm text-ink-secondary">{c.caption}</p>}
              {c.approval_state === 'approved' ? (
                <p className="mt-3 flex items-center gap-1.5 font-medium text-emerald"><CheckCircle2 size={16} /> Aprovado</p>
              ) : (
                <div className="mt-3 flex gap-2">
                  <Button onClick={() => approve(c)} disabled={busyId === c.id}>
                    <CheckCircle2 size={16} /> Aprovar
                  </Button>
                  <Button variant="outline" onClick={() => requestChanges(c)} disabled={busyId === c.id}>
                    <MessageSquare size={16} /> Pedir ajustes
                  </Button>
                </div>
              )}
              {c.approval_state === 'changes_requested' && (
                <p className="mt-2 text-sm text-amber-600">Ajustes solicitados: {c.client_feedback}</p>
              )}
            </div>
          ))}
        </div>
      </main>
    </div>
  )
}
