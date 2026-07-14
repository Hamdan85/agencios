// ─────────────────────────────────────────────────────────────────
// The iconographic vocabulary of agencios. Every status, channel,
// creative type and priority has a color + icon so the UI is
// self-explanatory at a glance. Import meta, render the icon.
// ─────────────────────────────────────────────────────────────────
import {
  Lightbulb, Ruler, Wand2, ShieldCheck, CalendarClock, Radio, LineChart, CheckCircle2,
  Camera, AtSign, PlaySquare, Briefcase, Music2, Hash,
  Film, Image as ImageIcon, GalleryHorizontalEnd, Clapperboard, Megaphone,
  Sparkles, Video, LayoutTemplate,
  FileText, FileSpreadsheet, Presentation, FileArchive, File as FileIcon, Paperclip,
  UploadCloud, AlertTriangle,
} from 'lucide-react'
import { InstagramIcon } from './brand-icons.jsx'
import i18n from '@/i18n'

// Labels resolve at ACCESS time (property getters bound to i18next), so every
// existing `.label` / `.hint` read across the app follows the active language
// without touching the call sites. Keys live in locales/<locale>/common.json.
const tc = (key) => i18n.t(key, { ns: 'common' })

// Adds `fields` as getters resolving `${prefix}.${field}` (e.g. status.ideation.label).
const localized = (base, prefix, fields) => {
  for (const field of fields) {
    Object.defineProperty(base, field, { get: () => tc(`${prefix}.${field}`), enumerable: true })
  }
  return base
}

// Adds a single `label` getter resolving the given key directly.
const withLabel = (base, key) => {
  Object.defineProperty(base, 'label', { get: () => tc(key), enumerable: true })
  return base
}

// A plain { key: string } map whose values resolve `${prefix}.${key}` lazily.
const localizedStrings = (prefix, keys) => {
  const out = {}
  for (const key of keys) {
    Object.defineProperty(out, key, { get: () => tc(`${prefix}.${key}`), enumerable: true })
  }
  return out
}

// lucide v1 removed brand icons (trademark) — channel identity is carried by
// the vivid colors below; icons are recognizable generics.
const Instagram = InstagramIcon
const Facebook = AtSign
const Youtube = PlaySquare
const Linkedin = Briefcase
const Twitter = Hash

// The eight funnel statuses — order IS the workflow (mirrors Ticket::WORKFLOW).
export const WORKFLOW = ['ideation', 'scoping', 'production', 'approval', 'scheduled', 'published', 'retrospective', 'done']

export const STATUS_META = {
  ideation:      localized({ color: '#F59E0B', icon: Lightbulb },     'status.ideation',      ['label', 'short', 'hint']),
  scoping:       localized({ color: '#0EA5E9', icon: Ruler },         'status.scoping',       ['label', 'short', 'hint']),
  production:    localized({ color: '#7C3AED', icon: Wand2 },         'status.production',    ['label', 'short', 'hint']),
  approval:      localized({ color: '#F97316', icon: ShieldCheck },   'status.approval',      ['label', 'short', 'hint']),
  scheduled:     localized({ color: '#EC4899', icon: CalendarClock }, 'status.scheduled',     ['label', 'short', 'hint']),
  published:     localized({ color: '#10B981', icon: Radio },         'status.published',     ['label', 'short', 'hint']),
  retrospective: localized({ color: '#6366F1', icon: LineChart },     'status.retrospective', ['label', 'short', 'hint']),
  done:          localized({ color: '#14B8A6', icon: CheckCircle2 },  'status.done',          ['label', 'short', 'hint']),
}

// Post lifecycle status (Post#status enum: scheduled / publishing / published /
// failed) — user-facing label + color + icon. Distinct from the ticket
// funnel STATUS_META: a post is one network's scheduled/live item, not a ticket.
export const POST_STATUS_META = {
  scheduled:  localized({ color: '#F59E0B', icon: CalendarClock }, 'postStatus.scheduled',  ['label', 'hint']),
  publishing: localized({ color: '#0EA5E9', icon: UploadCloud },   'postStatus.publishing', ['label', 'hint']),
  published:  localized({ color: '#10B981', icon: Radio },         'postStatus.published',  ['label', 'hint']),
  failed:     localized({ color: '#F43F5E', icon: AlertTriangle }, 'postStatus.failed',     ['label', 'hint']),
}
export const postStatusMeta = (key) => POST_STATUS_META[key] || POST_STATUS_META.scheduled

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
  reel:       withLabel({ color: '#EC4899', icon: Film,                 networks: ['instagram', 'tiktok', 'youtube'] }, 'creativeType.reel'),
  feed_image: withLabel({ color: '#0EA5E9', icon: ImageIcon,            networks: ['instagram', 'facebook', 'linkedin'] }, 'creativeType.feed_image'),
  carousel:   withLabel({ color: '#7C3AED', icon: GalleryHorizontalEnd, networks: ['instagram', 'linkedin', 'facebook'] }, 'creativeType.carousel'),
  story:      withLabel({ color: '#F97316', icon: Clapperboard,         networks: ['instagram', 'facebook'] }, 'creativeType.story'),
  ugc_video:  withLabel({ color: '#F43F5E', icon: Video,                networks: ['instagram', 'tiktok', 'youtube'] }, 'creativeType.ugc_video'),
  ad:         withLabel({ color: '#10B981', icon: Megaphone,            networks: ['instagram', 'facebook', 'linkedin'] }, 'creativeType.ad'),
  thumbnail:  withLabel({ color: '#6366F1', icon: LayoutTemplate,       networks: ['youtube'] }, 'creativeType.thumbnail'),
  cover:      withLabel({ color: '#14B8A6', icon: Camera,               networks: ['instagram', 'facebook', 'linkedin', 'youtube'] }, 'creativeType.cover'),
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
  low:    withLabel({ color: '#8B86A3', dot: '#B6B1C9' }, 'priority.low'),
  medium: withLabel({ color: '#0EA5E9', dot: '#0EA5E9' }, 'priority.medium'),
  high:   withLabel({ color: '#F43F5E', dot: '#F43F5E' }, 'priority.high'),
}

// Generation kinds. `metered` mirrors the fixed credit-cost constants in the
// backend Pricing module (app/models/pricing.rb): image, video, and carousel all
// consume prepaid credits — see the credit gate in Controllers::Creatives::Generate.
export const GENERATION_KIND_META = {
  carousel: withLabel({ color: '#7C3AED', icon: GalleryHorizontalEnd, metered: true }, 'generationKind.carousel'),
  video:    withLabel({ color: '#F43F5E', icon: Video,                metered: true }, 'generationKind.video'),
  image:    withLabel({ color: '#0EA5E9', icon: Sparkles,             metered: true }, 'generationKind.image'),
}

// A generatable creative type's generation kind — mirrors each backend spec's
// `kind` (app/services/creatives/*.rb). `cover` is upload-only (not generatable)
// so it is intentionally absent.
export const GENERATION_KIND_FOR_TYPE = {
  reel: 'video',
  ugc_video: 'video',
  feed_image: 'image',
  story: 'image',
  ad: 'image',
  thumbnail: 'image',
  carousel: 'carousel',
}

export const PLAN_META = {
  solo:       withLabel({ color: '#0EA5E9' }, 'plan.solo'),
  agencia:    withLabel({ color: '#7C3AED' }, 'plan.agencia'),
  enterprise: withLabel({ color: '#EC4899' }, 'plan.enterprise'),
}

export const ROLE_LABELS = localizedStrings('role', ['owner', 'admin', 'manager', 'member', 'guest'])

// Attachment kinds (derived on the backend from the blob content type). Each
// maps to a color + icon for the file grid, and tells the viewer how to render.
export const ATTACHMENT_KIND_META = {
  image:        withLabel({ color: '#0EA5E9', icon: ImageIcon },       'attachmentKind.image'),
  video:        withLabel({ color: '#EC4899', icon: Film },            'attachmentKind.video'),
  audio:        withLabel({ color: '#8B5CF6', icon: Music2 },          'attachmentKind.audio'),
  pdf:          withLabel({ color: '#EF4444', icon: FileText },        'attachmentKind.pdf'),
  document:     withLabel({ color: '#2563EB', icon: FileText },        'attachmentKind.document'),
  spreadsheet:  withLabel({ color: '#16A34A', icon: FileSpreadsheet }, 'attachmentKind.spreadsheet'),
  presentation: withLabel({ color: '#F97316', icon: Presentation },    'attachmentKind.presentation'),
  archive:      withLabel({ color: '#A16207', icon: FileArchive },     'attachmentKind.archive'),
  file:         withLabel({ color: '#8B86A3', icon: FileIcon },        'attachmentKind.file'),
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

// The creative types a manual UPLOAD should offer for a ticket: the types it
// scoped, kept only if they fit the ticket's channels — so a reel or a TikTok
// ticket never offers a carousel. Falls back to the channel-fit set when the
// ticket hasn't scoped types yet, and never returns empty.
export const uploadableTypesForTicket = (scopedTypes = [], channels = []) => {
  const fit = creativeTypesForChannels(channels)
  const scoped = (Array.isArray(scopedTypes) ? scopedTypes : []).filter(Boolean)
  const allowed = scoped.length ? scoped.filter((t) => fit.includes(t)) : fit
  return allowed.length ? allowed : fit
}

// The generation kinds a ticket can produce with AI: the generation kinds of its
// generatable creative types — narrowed to its channels the same way uploads are.
// A carousel-only ticket yields ['carousel'] (never video/image); a TikTok ticket
// (video-only types) yields ['video']. Preserves GENERATION_KIND_META order.
export const generatableKindsForTicket = (scopedTypes = [], channels = []) => {
  const kinds = new Set(
    uploadableTypesForTicket(scopedTypes, channels)
      .map((t) => GENERATION_KIND_FOR_TYPE[t])
      .filter(Boolean),
  )
  return Object.keys(GENERATION_KIND_META).filter((k) => kinds.has(k))
}

// ─────────────────────────────────────────────────────────────────
// Client positioning wizard. Keys stay English (they map 1:1 to
// Client::POSITIONING_KEYS on the backend); labels/placeholders are
// user-facing PT-BR. `content_pillars` is the only array field (one
// pillar per line). These steps come AFTER the contact step in the
// creation wizard, and stand alone in the client-page editor.
// ─────────────────────────────────────────────────────────────────
const positioningField = (key, type) =>
  localized({ key, type }, `positioning.fields.${key}`, ['label', 'placeholder'])

const positioningStep = (key, fields) =>
  localized({ key, fields }, `positioning.${key}`, ['title', 'description'])

export const POSITIONING_STEPS = [
  positioningStep('identity', [
    positioningField('one_liner', 'textarea'),
    positioningField('category', 'text'),
    positioningField('mission', 'textarea'),
  ]),
  positioningStep('audience', [
    positioningField('target_audience', 'textarea'),
    positioningField('audience_pain', 'textarea'),
  ]),
  positioningStep('differentiation', [
    positioningField('value_proposition', 'textarea'),
    positioningField('differentiators', 'textarea'),
    positioningField('competitors', 'text'),
  ]),
  positioningStep('content', [
    positioningField('content_pillars', 'pillars'),
    positioningField('keywords', 'text'),
    positioningField('guardrails', 'textarea'),
  ]),
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
  carousel_style: 'gradient',
}

// All positioning field metadata flattened (used to render the read view).
export const POSITIONING_FIELDS = POSITIONING_STEPS.flatMap((s) => s.fields)
