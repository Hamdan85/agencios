// ─────────────────────────────────────────────────────────────────
// The iconographic vocabulary of agencios. Every status, channel,
// creative type and priority has a color + icon so the UI is
// self-explanatory at a glance. Import meta, render the icon.
// ─────────────────────────────────────────────────────────────────
import {
  Lightbulb, Ruler, Wand2, CalendarClock, Radio, LineChart, CheckCircle2,
  Camera, AtSign, PlaySquare, Briefcase, Music2, Hash,
  Film, Image as ImageIcon, GalleryHorizontalEnd, Clapperboard, Megaphone,
  Sparkles, Video, LayoutTemplate,
  FileText, FileSpreadsheet, Presentation, FileArchive, File as FileIcon, Paperclip,
} from 'lucide-react'
import { InstagramIcon } from './brand-icons.jsx'

// lucide v1 removed brand icons (trademark) — channel identity is carried by
// the vivid colors below; icons are recognizable generics.
const Instagram = InstagramIcon
const Facebook = AtSign
const Youtube = PlaySquare
const Linkedin = Briefcase
const Twitter = Hash

// The seven funnel statuses — order IS the workflow.
export const WORKFLOW = ['ideation', 'scoping', 'production', 'scheduled', 'published', 'retrospective', 'done']

export const STATUS_META = {
  ideation:      { label: 'Ideação',        short: 'Ideação',    color: '#F59E0B', icon: Lightbulb,     hint: 'Brief, objetivo e audiência' },
  scoping:       { label: 'Escopo',         short: 'Escopo',     color: '#0EA5E9', icon: Ruler,        hint: 'Tipo, canais e entregáveis' },
  production:    { label: 'Produção',       short: 'Produção',   color: '#7C3AED', icon: Wand2,        hint: 'Criativo e legenda' },
  scheduled:     { label: 'Postagem',       short: 'Postagem',   color: '#EC4899', icon: CalendarClock, hint: 'Escolha o criativo e publique — agora ou agendado' },
  published:     { label: 'No ar',          short: 'No ar',      color: '#10B981', icon: Radio,        hint: 'No ar — monitorando' },
  retrospective: { label: 'Retrospectiva',  short: 'Retro',      color: '#6366F1', icon: LineChart,    hint: 'Lições aprendidas' },
  done:          { label: 'Concluído',      short: 'Concluído',  color: '#14B8A6', icon: CheckCircle2, hint: 'Arquivado com métricas' },
}

export const CHANNEL_META = {
  instagram: { label: 'Instagram', color: '#E1306C', icon: Instagram },
  facebook:  { label: 'Facebook',  color: '#1877F2', icon: Facebook },
  threads:   { label: 'Threads',   color: '#000000', icon: AtSign },
  tiktok:    { label: 'TikTok',    color: '#111111', icon: Music2 },
  youtube:   { label: 'YouTube',   color: '#FF0000', icon: Youtube },
  linkedin:  { label: 'LinkedIn',  color: '#0A66C2', icon: Linkedin },
  x:         { label: 'X',         color: '#111111', icon: Twitter },
}

// `networks` mirrors each creative spec's `network_fit` on the backend
// (app/services/creatives/*.rb). A creative type is NOT channel-agnostic — a
// reel only makes sense on Instagram/TikTok/YouTube — so the type picker is
// derived from the channels chosen for the ticket (see creativeTypesForChannels).
export const CREATIVE_TYPE_META = {
  reel:       { label: 'Reel',         color: '#EC4899', icon: Film,                  networks: ['instagram', 'tiktok', 'youtube'] },
  feed_image: { label: 'Imagem',       color: '#0EA5E9', icon: ImageIcon,            networks: ['instagram', 'facebook', 'linkedin'] },
  carousel:   { label: 'Carrossel',    color: '#7C3AED', icon: GalleryHorizontalEnd, networks: ['instagram', 'linkedin', 'facebook'] },
  story:      { label: 'Story',        color: '#F97316', icon: Clapperboard,         networks: ['instagram', 'facebook'] },
  ugc_video:  { label: 'Vídeo UGC',    color: '#F43F5E', icon: Video,                networks: ['instagram', 'tiktok', 'youtube'] },
  ad:         { label: 'Anúncio',      color: '#10B981', icon: Megaphone,            networks: ['instagram', 'facebook', 'linkedin'] },
  thumbnail:  { label: 'Thumbnail',    color: '#6366F1', icon: LayoutTemplate,       networks: ['youtube'] },
  cover:      { label: 'Capa',         color: '#14B8A6', icon: Camera,               networks: ['instagram', 'facebook', 'linkedin', 'youtube'] },
}

// Which media a manual upload accepts per creative type — mirrors
// Creatives.accepted_upload_media (backend). Video types take video; image/
// carousel types take images; a story takes either; a cover is an image.
export const CREATIVE_UPLOAD_MEDIA = {
  reel: ['video'],
  ugc_video: ['video'],
  feed_image: ['image'],
  carousel: ['image'],
  ad: ['image'],
  thumbnail: ['image'],
  cover: ['image'],
  story: ['image', 'video'],
}

// The <input accept> string for a creative type's upload (e.g. "video/*").
export const uploadAcceptFor = (type) =>
  (CREATIVE_UPLOAD_MEDIA[type] || ['image', 'video']).map((m) => `${m}/*`).join(',')

// True when a picked File's media matches the creative type.
export const fileMatchesCreativeType = (file, type) =>
  (CREATIVE_UPLOAD_MEDIA[type] || ['image', 'video']).includes((file?.type || '').split('/')[0])

export const PRIORITY_META = {
  low:    { label: 'Baixa',  color: '#8B86A3', dot: '#B6B1C9' },
  medium: { label: 'Média',  color: '#0EA5E9', dot: '#0EA5E9' },
  high:   { label: 'Alta',   color: '#F43F5E', dot: '#F43F5E' },
}

export const GENERATION_KIND_META = {
  carousel: { label: 'Carrossel', color: '#7C3AED', icon: GalleryHorizontalEnd },
  video:    { label: 'Vídeo',     color: '#F43F5E', icon: Video },
  image:    { label: 'Imagem',    color: '#0EA5E9', icon: Sparkles },
}

export const PLAN_META = {
  solo:       { label: 'Solo',       color: '#0EA5E9' },
  agencia:    { label: 'Agência',    color: '#7C3AED' },
  enterprise: { label: 'Enterprise', color: '#EC4899' },
}

export const ROLE_LABELS = {
  owner: 'Dono', admin: 'Admin', manager: 'Gestor', member: 'Membro', guest: 'Convidado',
}

// Attachment kinds (derived on the backend from the blob content type). Each
// maps to a color + icon for the file grid, and tells the viewer how to render.
export const ATTACHMENT_KIND_META = {
  image:        { label: 'Imagem',       color: '#0EA5E9', icon: ImageIcon },
  video:        { label: 'Vídeo',        color: '#EC4899', icon: Film },
  audio:        { label: 'Áudio',        color: '#8B5CF6', icon: Music2 },
  pdf:          { label: 'PDF',          color: '#EF4444', icon: FileText },
  document:     { label: 'Documento',    color: '#2563EB', icon: FileText },
  spreadsheet:  { label: 'Planilha',     color: '#16A34A', icon: FileSpreadsheet },
  presentation: { label: 'Apresentação', color: '#F97316', icon: Presentation },
  archive:      { label: 'Arquivo',      color: '#A16207', icon: FileArchive },
  file:         { label: 'Arquivo',      color: '#8B86A3', icon: FileIcon },
}

export const ATTACHMENT_ICON = Paperclip

export const attachmentKindMeta = (key) => ATTACHMENT_KIND_META[key] || ATTACHMENT_KIND_META.file

// Mirrors Publishers::SocialPublisher::SUPPORTED_MEDIA — which media kinds each
// network can publish. TikTok/YouTube are video-only.
export const SUPPORTED_MEDIA = {
  instagram: ['image', 'carousel', 'video'],
  facebook:  ['image', 'carousel', 'video', 'text'],
  threads:   ['image', 'carousel', 'video', 'text'],
  tiktok:    ['video'],
  youtube:   ['video'],
  linkedin:  ['image', 'carousel', 'video', 'text'],
  x:         ['image', 'carousel', 'video', 'text'],
}

// Mirrors Creative#media_kind: derive the publishable media kind of a creative.
export const creativeMediaKind = (creative) => {
  const urls = creative?.asset_urls || []
  if (urls.some((u) => /\.(mp4|mov|webm|avi)(\?|$)/i.test(u))) return 'video'
  if (creative?.creative_type === 'carousel' || urls.length > 1) return 'carousel'
  if (urls.length === 1) return 'image'
  return 'text'
}

// Which of the given channels can actually receive this creative's media.
export const channelsForCreative = (creative, channels = []) => {
  const kind = creativeMediaKind(creative)
  return channels.filter((ch) => (SUPPORTED_MEDIA[ch] || []).includes(kind))
}

// Mirrors Ticket::COVER_TYPES — image creative types that ride a video post as
// its cover/thumbnail rather than posting standalone.
export const COVER_TYPES = ['thumbnail', 'cover']
export const isCoverType = (type) => COVER_TYPES.includes(type)

// Mirrors Publishers::SocialPublisher::THUMBNAIL_CAPABLE — networks where a still
// image can be attached to a video post as its cover/thumbnail.
export const THUMBNAIL_CAPABLE = ['instagram', 'youtube']

// Mirror of Operations::Tickets::Publish#plan_channel: given the selected
// creatives (one per scoped type) and the ticket's channels, resolve what will
// actually post on each channel — dropping unsupported media and pairing a cover
// image onto the video post where the network supports it. Returns one entry per
// channel: { channel, posts: [{ creative, cover }], skipped: [creative] }.
export const resolvePostRouting = (creatives, channels = []) => {
  const list = (Array.isArray(creatives) ? creatives : []).filter(Boolean)
  return (Array.isArray(channels) ? channels : []).map((channel) => {
    const supported = SUPPORTED_MEDIA[channel] || []
    const hasVideo = list.some((c) => creativeMediaKind(c) === 'video' && supported.includes('video'))
    const cover = list.find((c) => isCoverType(c.creative_type))
    const attachCover = !!cover && hasVideo && THUMBNAIL_CAPABLE.includes(channel)

    const posts = []
    const skipped = []
    list.forEach((c) => {
      if (isCoverType(c.creative_type)) return
      const kind = creativeMediaKind(c)
      if (supported.includes(kind)) posts.push({ creative: c, cover: attachCover && kind === 'video' ? cover : null })
      else skipped.push(c)
    })
    if (cover && !attachCover) {
      if (supported.includes(creativeMediaKind(cover))) posts.push({ creative: cover, cover: null })
      else skipped.push(cover)
    }
    return { channel, posts, skipped }
  })
}

export const statusMeta = (key) => STATUS_META[key] || STATUS_META.ideation
export const channelMeta = (key) => CHANNEL_META[key] || { label: key, color: '#8B86A3', icon: Radio }
export const creativeMeta = (key) => CREATIVE_TYPE_META[key] || { label: key || '—', color: '#8B86A3', icon: ImageIcon }

// The creative types that fit the given channels. With no channel selected we
// fall back to every type (nothing to narrow by yet); otherwise we keep only the
// types whose `networks` intersect the chosen channels.
export const creativeTypesForChannels = (channels) => {
  const chosen = (Array.isArray(channels) ? channels : []).filter(Boolean)
  const keys = Object.keys(CREATIVE_TYPE_META)
  if (chosen.length === 0) return keys
  return keys.filter((key) => CREATIVE_TYPE_META[key].networks?.some((n) => chosen.includes(n)))
}

// ─────────────────────────────────────────────────────────────────
// Client positioning wizard. Keys stay English (they map 1:1 to
// Client::POSITIONING_KEYS on the backend); labels/placeholders are
// user-facing PT-BR. `content_pillars` is the only array field (one
// pillar per line). These steps come AFTER the contact step in the
// creation wizard, and stand alone in the client-page editor.
// ─────────────────────────────────────────────────────────────────
export const POSITIONING_STEPS = [
  {
    key: 'identity',
    title: 'Identidade & mercado',
    description: 'O que a marca é e onde compete.',
    fields: [
      { key: 'one_liner', label: 'O que faz (em uma frase)', type: 'textarea', placeholder: 'Ex.: Ajudamos pequenas confeitarias a venderem mais pelo Instagram.' },
      { key: 'category', label: 'Categoria / mercado', type: 'text', placeholder: 'Ex.: Confeitaria artesanal premium' },
      { key: 'mission', label: 'Missão / propósito', type: 'textarea', placeholder: 'O porquê da marca existir.' },
    ],
  },
  {
    key: 'audience',
    title: 'Audiência',
    description: 'Para quem a marca fala.',
    fields: [
      { key: 'target_audience', label: 'Público-alvo (ICP)', type: 'textarea', placeholder: 'Quem é o cliente ideal: perfil, faixa, contexto.' },
      { key: 'audience_pain', label: 'Dor / problema que resolve', type: 'textarea', placeholder: 'A principal dor que a marca elimina.' },
    ],
  },
  {
    key: 'differentiation',
    title: 'Diferenciação',
    description: 'Por que escolher esta marca.',
    fields: [
      { key: 'value_proposition', label: 'Proposta de valor', type: 'textarea', placeholder: 'A promessa única e o benefício central.' },
      { key: 'differentiators', label: 'Diferenciais', type: 'textarea', placeholder: 'O que a torna diferente da concorrência.' },
      { key: 'competitors', label: 'Concorrentes', type: 'text', placeholder: 'Principais concorrentes ou alternativas.' },
    ],
  },
  {
    key: 'content',
    title: 'Conteúdo',
    description: 'Como a marca se comunica.',
    fields: [
      { key: 'content_pillars', label: 'Pilares de conteúdo', type: 'pillars', placeholder: 'Um pilar por linha (ex.: bastidores, dicas, prova social).' },
      { key: 'keywords', label: 'Palavras-chave / hashtags', type: 'text', placeholder: 'Termos e hashtags recorrentes.' },
      { key: 'guardrails', label: 'Restrições / o que evitar', type: 'textarea', placeholder: 'Assuntos, palavras ou abordagens proibidas.' },
    ],
  },
]

// Empty positioning shape — every key the wizard tracks (statement is the
// AI-synthesized field on the final step). content_pillars is an array.
export const EMPTY_POSITIONING = {
  one_liner: '', category: '', mission: '',
  target_audience: '', audience_pain: '',
  value_proposition: '', differentiators: '', competitors: '',
  content_pillars: [], keywords: '', guardrails: '',
  statement: '',
}

// Brand identity (voice, @handle, colors) lives on the client itself — distinct
// from the strategic positioning. Logo + creator avatar upload separately.
export const EMPTY_BRAND = {
  brand_voice: '',
  default_handle: '',
  brand_primary_color: '#7C3AED',
  brand_secondary_color: '#F59E0B',
}

// All positioning field metadata flattened (used to render the read view).
export const POSITIONING_FIELDS = POSITIONING_STEPS.flatMap((s) => s.fields)
