import { useState } from 'react'
import {
  Settings, Palette, Users2, Plug, Save, AtSign, Sparkles, UserPlus,
  Link2, Check, Calendar, Wallet, Copy, ShieldCheck, Bot, Trash2, RefreshCw,
} from 'lucide-react'
import { toast } from 'sonner'
import {
  useSettings, useSettingsMutation, useWorkspaceMembers, useWorkspaceMutations,
  useConnections, useRevokeConnection, useMcpConnector, useRotateMcpConnector,
} from '@/hooks/useData'
import { PageHeader } from '@/components/ui/page-header'
import { Button } from '@/components/ui/button'
import { Input, Textarea } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Switch } from '@/components/ui/switch'
import { Avatar } from '@/components/ui/avatar'
import { PageLoader } from '@/components/ui/feedback'
import { Page } from '@/components/ui/page'
import {
  Tabs, TabsList, TabsTrigger, TabsContent,
} from '@/components/ui/tabs'
import {
  Select, SelectTrigger, SelectValue, SelectContent, SelectItem,
} from '@/components/ui/select'
import { ROLE_LABELS } from '@/lib/constants'

const ROLE_VARIANT = { owner: 'default', admin: 'soft', manager: 'success', member: 'outline', guest: 'muted' }

// ── Brand tab ──────────────────────────────────────────────────
function BrandTab({ data, mutation }) {
  const setting = data?.setting || {}
  const workspace = data?.workspace || {}
  const init = {
    name: workspace.name ?? data?.name ?? '',
    brand_voice: workspace.brand_voice ?? data?.brand_voice ?? '',
    default_handle: workspace.default_handle ?? data?.default_handle ?? '',
    brand_primary_color: workspace.brand_primary_color ?? data?.brand_primary_color ?? '#7C3AED',
    brand_secondary_color: workspace.brand_secondary_color ?? data?.brand_secondary_color ?? '#EC4899',
    brand_tone: setting.brand_tone ?? data?.brand_tone ?? '',
    auto_publish_default: setting.auto_publish_default ?? data?.auto_publish_default ?? false,
  }
  const [form, setForm] = useState(init)
  const set = (k) => (v) => setForm((f) => ({ ...f, [k]: v }))

  const submit = (e) => {
    e.preventDefault()
    mutation.mutate(form)
  }

  return (
    <form onSubmit={submit} className="grid grid-cols-1 gap-6 lg:grid-cols-3">
      <div className="space-y-6 lg:col-span-2">
        <Card>
          <CardHeader>
            <CardTitle>Identidade da agência</CardTitle>
            <CardDescription>Nome, voz e @ usados em legendas e criativos.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="st-name">Nome da agência</Label>
              <Input id="st-name" value={form.name} onChange={(e) => set('name')(e.target.value)} placeholder="Sua Agência" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="st-handle">@ padrão</Label>
              <div className="relative">
                <AtSign size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-faint" />
                <Input id="st-handle" value={form.default_handle} onChange={(e) => set('default_handle')(e.target.value)} className="pl-9" placeholder="suaagencia" />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="st-voice">Voz da marca</Label>
              <Textarea id="st-voice" value={form.brand_voice} onChange={(e) => set('brand_voice')(e.target.value)} placeholder="Descreva o tom e a personalidade da marca…" className="min-h-24" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="st-tone">Tom de comunicação</Label>
              <Input id="st-tone" value={form.brand_tone} onChange={(e) => set('brand_tone')(e.target.value)} placeholder="Ex: descontraído, inspirador" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Cores da marca</CardTitle>
            <CardDescription>Aplicadas em criativos gerados e na identidade visual.</CardDescription>
          </CardHeader>
          <CardContent className="grid grid-cols-2 gap-4">
            {[
              { key: 'brand_primary_color', label: 'Cor primária' },
              { key: 'brand_secondary_color', label: 'Cor secundária' },
            ].map(({ key, label }) => (
              <div key={key} className="space-y-1.5">
                <Label>{label}</Label>
                <div className="flex items-center gap-2 rounded-xl border border-border bg-surface-muted p-2">
                  <input
                    type="color"
                    value={form[key]}
                    onChange={(e) => set(key)(e.target.value)}
                    className="size-9 cursor-pointer rounded-lg border-0 bg-transparent p-0"
                    aria-label={label}
                  />
                  <input
                    value={form[key]}
                    onChange={(e) => set(key)(e.target.value)}
                    className="w-full bg-transparent font-mono text-sm uppercase text-ink outline-none"
                  />
                </div>
              </div>
            ))}
          </CardContent>
        </Card>

        <Card>
          <CardContent className="flex items-center justify-between gap-4 p-5">
            <div>
              <p className="font-display text-base font-bold text-ink">Publicação automática</p>
              <p className="text-sm text-ink-muted">Publicar posts automaticamente quando chegarem ao horário agendado.</p>
            </div>
            <Switch checked={!!form.auto_publish_default} onCheckedChange={set('auto_publish_default')} />
          </CardContent>
        </Card>

        <div className="flex justify-end">
          <Button type="submit" size="lg" disabled={mutation.isPending}>
            <Save size={18} /> {mutation.isPending ? 'Salvando…' : 'Salvar alterações'}
          </Button>
        </div>
      </div>

      {/* Live preview */}
      <div className="lg:col-span-1">
        <div className="sticky top-4">
          <Label className="mb-2 block">Pré-visualização</Label>
          <Card className="overflow-hidden">
            <div className="h-24 w-full" style={{ background: `linear-gradient(135deg, ${form.brand_primary_color}, ${form.brand_secondary_color})` }} />
            <CardContent className="-mt-8 pt-0">
              <div className="flex size-16 items-center justify-center rounded-2xl text-white shadow-lg ring-4 ring-surface" style={{ background: form.brand_primary_color }}>
                <Sparkles size={28} />
              </div>
              <h3 className="mt-3 font-display text-lg font-extrabold text-ink">{form.name || 'Sua Agência'}</h3>
              {form.default_handle && <p className="text-sm font-semibold" style={{ color: form.brand_primary_color }}>@{form.default_handle}</p>}
              {form.brand_voice && <p className="mt-2 line-clamp-3 text-sm text-ink-muted">{form.brand_voice}</p>}
              <div className="mt-4 flex gap-2">
                <span className="h-8 flex-1 rounded-lg" style={{ background: form.brand_primary_color }} />
                <span className="h-8 flex-1 rounded-lg" style={{ background: form.brand_secondary_color }} />
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </form>
  )
}

// ── Team tab ───────────────────────────────────────────────────
function TeamTab() {
  const { data: members, isLoading } = useWorkspaceMembers()
  const { invite } = useWorkspaceMutations()
  const [email, setEmail] = useState('')
  const [role, setRole] = useState('member')
  const [link, setLink] = useState(null)

  const list = members || []

  const submit = (e) => {
    e.preventDefault()
    if (!email.trim()) return
    invite.mutate({ email: email.trim(), role }, {
      onSuccess: (res) => {
        const inviteLink = res?.invitation?.link
        if (inviteLink) setLink(inviteLink)
        setEmail('')
      },
    })
  }

  const copyLink = async () => {
    try { await navigator.clipboard.writeText(link); toast.success('Link copiado!') } catch { /* noop */ }
  }

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
      <Card className="lg:col-span-2">
        <CardHeader>
          <CardTitle>Equipe</CardTitle>
          <CardDescription>Membros com acesso a este workspace.</CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          {isLoading ? (
            <div className="p-5"><PageLoader /></div>
          ) : (
            <div className="divide-y divide-border">
              {list.map((m) => (
                <div key={m.id} className="flex items-center justify-between gap-3 px-5 py-3.5">
                  <div className="flex items-center gap-3">
                    <Avatar name={m.name} src={m.avatar_url} size={40} />
                    <div>
                      <p className="font-semibold text-ink">{m.name || 'Membro'}</p>
                      <p className="text-xs text-ink-muted">{m.email}</p>
                    </div>
                  </div>
                  <Badge variant={ROLE_VARIANT[m.role] || 'outline'}>{ROLE_LABELS[m.role] || m.role}</Badge>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Card className="h-fit lg:col-span-1">
        <CardHeader>
          <div className="mb-1 flex size-10 items-center justify-center rounded-xl bg-brand-soft text-brand">
            <UserPlus size={20} />
          </div>
          <CardTitle>Convidar</CardTitle>
          <CardDescription>Gere um link de convite para um novo membro.</CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={submit} className="space-y-3.5">
            <div className="space-y-1.5">
              <Label htmlFor="inv-email">E-mail</Label>
              <Input id="inv-email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="pessoa@email.com" />
            </div>
            <div className="space-y-1.5">
              <Label>Papel</Label>
              <Select value={role} onValueChange={setRole}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {['admin', 'manager', 'member', 'guest'].map((r) => (
                    <SelectItem key={r} value={r}>{ROLE_LABELS[r]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <Button type="submit" className="w-full" disabled={invite.isPending}>
              <UserPlus size={16} /> {invite.isPending ? 'Gerando…' : 'Gerar convite'}
            </Button>
          </form>

          {link && (
            <div className="mt-4 rounded-xl border border-emerald/30 bg-emerald/8 p-3">
              <p className="mb-1.5 flex items-center gap-1.5 text-xs font-bold text-emerald">
                <Check size={13} /> Convite gerado — compartilhe o link:
              </p>
              <div className="flex items-center gap-2">
                <code className="flex-1 truncate rounded-lg bg-surface px-2 py-1.5 font-mono text-xs text-ink-secondary">{link}</code>
                <Button type="button" variant="outline" size="icon-sm" onClick={copyLink}><Copy size={14} /></Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

// ── Integrations tab ───────────────────────────────────────────
function IntegrationCard({ icon: Icon, color, name, connected, sub, onConnect }) {
  return (
    <Card className="flex flex-col p-5">
      <div className="flex items-start justify-between gap-2">
        <div className="flex size-11 items-center justify-center rounded-xl" style={{ background: `${color}16`, color }}>
          <Icon size={22} strokeWidth={2.2} />
        </div>
        {connected ? (
          <Badge variant="success"><Check size={12} /> Conectado</Badge>
        ) : (
          <Badge variant="muted">Desconectado</Badge>
        )}
      </div>
      <h3 className="mt-3 font-display text-base font-bold text-ink">{name}</h3>
      <p className="mt-0.5 min-h-[20px] text-sm text-ink-muted">{sub}</p>
      <div className="mt-4">
        {connected ? (
          <Button variant="outline" size="sm" className="w-full" disabled>
            <ShieldCheck size={15} /> Ativo
          </Button>
        ) : (
          <Button variant="solid" size="sm" className="w-full" onClick={onConnect}>
            <Link2 size={15} /> Conectar
          </Button>
        )}
      </div>
    </Card>
  )
}

function IntegrationsTab() {
  const { data: setting } = useSettings()

  const s = setting?.setting || setting || {}
  const stub = () => toast.info('Conexão indisponível nesta demonstração.')

  return (
    <div className="space-y-8">
      <section>
        <div className="mb-3 flex items-center gap-2">
          <Plug size={18} className="text-emerald" />
          <h2 className="font-display text-lg font-bold text-ink">Serviços</h2>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <IntegrationCard
            icon={Calendar}
            color="#0EA5E9"
            name="Google Calendar"
            connected={!!s.google_connected}
            sub="Sincronize reuniões e crie links do Meet."
            onConnect={stub}
          />
          <IntegrationCard
            icon={Wallet}
            color="#10B981"
            name="Mercado Pago"
            connected={!!s.mercadopago_connected}
            sub="Cobre seus clientes via Pix."
            onConnect={stub}
          />
        </div>
      </section>
    </div>
  )
}

// ── Connections tab (MCP connectors like Claude) ───────────────
function ConnectionsTab() {
  const { data: connections, isLoading } = useConnections()
  const revoke = useRevokeConnection()
  const { data: connector, isLoading: loadingConnector } = useMcpConnector()
  const rotate = useRotateMcpConnector()
  const [copied, setCopied] = useState(false)
  const [revealed, setRevealed] = useState(false)
  const url = connector?.url || ''
  // Mask the token in the displayed URL until revealed (it's a credential).
  const masked = url.replace(/\/mcp\/c\/.+$/, '/mcp/c/••••••••••••')

  const copy = () => {
    if (!url) return
    navigator.clipboard?.writeText(url)
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  const onRotate = () => {
    if (window.confirm('Gerar uma nova URL invalida a atual no Claude. Continuar?')) rotate.mutate()
  }

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
      <div className="space-y-6 lg:col-span-2">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Bot size={18} /> Conector do Claude</CardTitle>
            <CardDescription>
              Copie sua URL pessoal e adicione no Claude em <strong>Configurações → Conectores → Adicionar
              conector personalizado</strong>. A URL já contém sua credencial — não precisa de login nem OAuth.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-2.5">
            <Label>URL do conector</Label>
            <div className="flex flex-wrap items-center gap-2">
              <Input
                readOnly
                value={loadingConnector ? 'Carregando…' : (revealed ? url : masked)}
                className="min-w-0 flex-1 font-mono text-sm"
                onFocus={(e) => e.target.select()}
              />
              <Button type="button" variant="outline" onClick={() => setRevealed((v) => !v)}>
                {revealed ? 'Ocultar' : 'Revelar'}
              </Button>
              <Button type="button" variant="outline" onClick={copy} disabled={!url}>
                {copied ? <Check size={16} /> : <Copy size={16} />} {copied ? 'Copiado' : 'Copiar'}
              </Button>
            </div>
            <div className="flex items-center justify-between gap-2 pt-1">
              <p className="text-xs text-ink-faint">
                A URL é um segredo: quem a tiver opera seus workspaces com as suas permissões.
              </p>
              <Button type="button" variant="ghost" size="sm" className="shrink-0 text-ink-muted" onClick={onRotate} disabled={rotate.isPending}>
                <RefreshCw size={14} /> Gerar nova URL
              </Button>
            </div>
            <p className="text-xs text-ink-faint">
              No Claude: <strong className="text-ink-muted">Configurações → Conectores → Adicionar conector
              personalizado</strong> e cole a URL. Não pede login.
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><ShieldCheck size={18} /> Apps autorizados</CardTitle>
            <CardDescription>Aplicativos com acesso à sua conta via OAuth.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            {isLoading ? (
              <p className="text-sm text-ink-faint">Carregando…</p>
            ) : !connections?.length ? (
              <p className="text-sm text-ink-faint">Nenhum app conectado ainda.</p>
            ) : (
              connections.map((c) => (
                <div key={c.id} className="flex items-center justify-between rounded-lg border border-line p-3">
                  <div className="space-y-1.5">
                    <div className="flex items-center gap-2 font-semibold">
                      {c.name}
                      {c.dynamically_registered && <Badge variant="muted">auto</Badge>}
                    </div>
                    <div className="flex flex-wrap gap-1">
                      {c.scopes.map((s) => <Badge key={s} variant="outline">{s}</Badge>)}
                    </div>
                  </div>
                  <Button type="button" variant="ghost" className="text-danger" onClick={() => revoke.mutate(c.id)} disabled={revoke.isPending}>
                    <Trash2 size={16} /> Revogar
                  </Button>
                </div>
              ))
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

export default function SettingsIndex() {
  const { data, isLoading } = useSettings()
  const mutation = useSettingsMutation()

  if (isLoading) return <PageLoader />

  return (
    <Page>
      <PageHeader
        eyebrow="Conta"
        title="Configurações"
        icon={Settings}
        color="#7C3AED"
        description="Marca, equipe e integrações do workspace."
      />

      <Tabs defaultValue="brand">
        <TabsList className="mb-6">
          <TabsTrigger value="brand"><Palette size={15} /> Marca</TabsTrigger>
          <TabsTrigger value="team"><Users2 size={15} /> Equipe</TabsTrigger>
          <TabsTrigger value="integrations"><Plug size={15} /> Integrações</TabsTrigger>
          <TabsTrigger value="connections"><Bot size={15} /> Conexões</TabsTrigger>
        </TabsList>

        <TabsContent value="brand" className="animate-rise">
          <BrandTab key={JSON.stringify({ w: data?.workspace, s: data?.setting })} data={data} mutation={mutation} />
        </TabsContent>
        <TabsContent value="team" className="animate-rise">
          <TeamTab />
        </TabsContent>
        <TabsContent value="integrations" className="animate-rise">
          <IntegrationsTab />
        </TabsContent>
        <TabsContent value="connections" className="animate-rise">
          <ConnectionsTab />
        </TabsContent>
      </Tabs>
    </Page>
  )
}
