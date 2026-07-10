import { useEffect, useState } from 'react'
import { ChevronLeft, ChevronRight, GalleryHorizontalEnd } from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from '@/components/ui/dialog'
import { cn } from '@/lib/utils'
import { CAROUSEL_STYLE_LABEL } from './positioningFields'

// The generated slide is authored on a 1080px-wide canvas (see the backend
// Creatives::CarouselSlideTemplate). We reproduce every measurement faithfully by
// expressing it as a fraction of the container width via CSS container-query
// units — so this on-screen slide is a true 1:1 miniature of the real output,
// not an approximation.
const DESIGN_W = 1080
const u = (px) => `${((px / DESIGN_W) * 100).toFixed(4)}cqw`

// Darken/lighten a #rrggbb hex — mirrors CarouselSlideTemplate#shade so the
// gradient matches the rendered slide exactly.
function shade(hex, pct) {
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || '').trim())
  if (!m) return hex || '#7C3AED'
  const n = parseInt(m[1], 16)
  const adj = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((c) =>
    Math.min(255, Math.max(0, Math.round(c + (255 * pct) / 100))),
  )
  return `#${adj.map((c) => c.toString(16).padStart(2, '0')).join('')}`
}

function initialsOf(name) {
  const parts = String(name || '').split(/\s+/).filter(Boolean).slice(0, 2)
  return parts.map((w) => w[0]).join('').toUpperCase() || '•'
}

// One faithful carousel slide — the exact layout the headless renderer produces,
// themed with the client's real brand identity (colors, @handle, avatar, logo)
// and carousel style (gradient / white / image).
export function CarouselSlide({ slide, index, total, client, className }) {
  const primary = client?.brand_primary_color || '#7C3AED'
  const secondary = client?.brand_secondary_color || '#F59E0B'
  const style = client?.carousel_style || 'gradient'
  const imageUrl = style === 'image' ? client?.carousel_background_url : null
  const hasImage = !!imageUrl
  const white = style === 'white' && !hasImage

  const isHook = index === 1
  const isCta = index === total
  const hl = isHook ? 92 : isCta ? 84 : 72

  const ink = white ? '#18161d' : '#ffffff'
  const bg = white
    ? '#ffffff'
    : hasImage
      ? '#2b2730'
      : `radial-gradient(120% 120% at 0% 0%, ${primary} 0%, ${shade(primary, -28)} 70%)`
  const shadow = hasImage ? '0 2px 12px rgba(0,0,0,.55)' : undefined
  const hlShadow = hasImage ? '0 4px 24px rgba(0,0,0,.65)' : undefined

  const handle = String(client?.default_handle || '').replace(/^@/, '')

  return (
    <div
      className={cn('relative overflow-hidden rounded-xl ring-1 ring-black/5', className)}
      style={{ containerType: 'inline-size', aspectRatio: '4 / 5', width: '100%', background: bg, color: ink }}
    >
      {hasImage && (
        <img src={imageUrl} alt="" className="absolute inset-0 size-full object-cover" />
      )}
      <div
        className="absolute inset-0 flex flex-col"
        style={{ padding: `${u(120)} ${u(64)} ${u(160)}` }}
      >
        {/* header: avatar + name/@handle · counter */}
        <div className="flex items-center justify-between">
          <div className="flex items-center" style={{ gap: u(20) }}>
            {client?.default_creator_avatar_url ? (
              <img
                src={client.default_creator_avatar_url}
                alt=""
                className="shrink-0 rounded-full object-cover"
                style={{ width: u(96), height: u(96), border: `${u(4)} solid rgba(255,255,255,.9)` }}
              />
            ) : (
              <div
                className="flex shrink-0 items-center justify-center rounded-full font-extrabold"
                style={{ width: u(96), height: u(96), background: secondary, color: '#fff', fontSize: u(40) }}
              >
                {initialsOf(client?.name)}
              </div>
            )}
            <div className="flex flex-col" style={{ lineHeight: 1.15 }}>
              <span className="font-extrabold" style={{ fontSize: u(36), textShadow: shadow }}>{client?.name || 'Sua marca'}</span>
              {handle && <span className="font-semibold" style={{ fontSize: u(28), opacity: 0.82, textShadow: shadow }}>@{handle}</span>}
            </div>
          </div>
          <span
            className="font-bold"
            style={{
              fontSize: u(30), opacity: 0.8, textShadow: shadow,
              background: white ? 'rgba(0,0,0,.05)' : 'rgba(255,255,255,.16)',
              color: white ? '#18161d' : undefined,
              padding: `${u(8)} ${u(20)}`, borderRadius: '999px',
            }}
          >
            {index}/{total}
          </span>
        </div>

        {/* body: kicker (cta) · headline · text */}
        <div className="flex flex-1 flex-col justify-center" style={{ gap: u(32) }}>
          {isCta && (
            <span
              className="self-start font-extrabold uppercase"
              style={{ fontSize: u(30), letterSpacing: u(2), color: secondary, textShadow: shadow }}
            >
              Próximo passo
            </span>
          )}
          <div>
            <h1
              className="font-extrabold"
              style={{ fontSize: u(hl), lineHeight: 1.05, maxWidth: '18ch', textWrap: 'balance', textShadow: hlShadow }}
            >
              {slide.headline}
            </h1>
            {!hasImage && (
              <div style={{ width: u(140), height: u(10), marginTop: u(28), borderRadius: '999px', background: secondary }} />
            )}
          </div>
          {slide.body && (
            <p style={{ fontSize: u(44), lineHeight: 1.4, opacity: 0.92, maxWidth: '24ch', textShadow: shadow }}>
              {slide.body}
            </p>
          )}
        </div>

        {/* footer: swipe hint · logo */}
        <div className="flex items-center justify-between">
          <span
            className="font-bold"
            style={{ fontSize: u(30), opacity: 0.85, borderTop: `${u(4)} solid ${secondary}`, paddingTop: u(16), textShadow: shadow }}
          >
            {isCta ? 'Salve e compartilhe' : 'Arraste →'}
          </span>
          {client?.logo_url && (
            <img src={client.logo_url} alt="" style={{ height: u(64), width: 'auto', objectFit: 'contain', opacity: 0.95 }} />
          )}
        </div>
      </div>
    </div>
  )
}

// Example slide copy for a client, mirroring the real structure
// (Prompts::CarouselCopy): slide 1 = hook, middle slides = one value point each,
// last = CTA. Built from the client's positioning when present so the example is
// tailored — the real copy is written by the AI, but the shape is identical.
export function buildExampleSlides(client) {
  const pos = client?.positioning || {}
  const brand = client?.name || 'a marca'
  const pillars = (Array.isArray(pos.content_pillars) ? pos.content_pillars : []).map((p) => String(p || '').trim()).filter(Boolean)
  const oneLiner = String(pos.one_liner || '').trim()
  const value = String(pos.value_proposition || '').trim()
  const pain = String(pos.audience_pain || '').trim()

  const clip = (s, n = 60) => (s.length <= n ? s : `${s.slice(0, n - 1).trimEnd()}…`)
  const cap = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s)

  const points = (pillars.length ? pillars : [
    'Estratégia sob medida para a sua marca',
    'Execução que economiza o seu tempo',
    'Resultados que você acompanha de perto',
  ]).slice(0, 4)

  const hook = {
    role: 'hook',
    headline: clip(pain ? cap(pain) : `Conheça a ${brand}`),
    body: clip(oneLiner || value || 'Arraste para ver como podemos ajudar você.', 90),
  }
  const valueSlides = points.map((p) => ({ role: 'value', headline: clip(cap(p)) }))
  const cta = {
    role: 'cta',
    headline: 'Bora começar?',
    body: clip(client?.default_handle ? `Siga @${String(client.default_handle).replace(/^@/, '')} e fale com a gente.` : 'Fale com a gente e comece hoje.', 90),
  }

  return [hook, ...valueSlides, cta]
}

// A full, paged example carousel — exactly the format generated for this client,
// so the team can see the real output before generating anything. Purely
// illustrative (the copy is example content; the AI writes the real words).
export function CarouselExampleDialog({ client, open, onOpenChange }) {
  const slides = buildExampleSlides(client)
  const total = slides.length
  const [i, setI] = useState(0)

  useEffect(() => { if (open) setI(0) }, [open])

  const go = (n) => setI((cur) => Math.min(total - 1, Math.max(0, cur + n)))
  const styleLabel = CAROUSEL_STYLE_LABEL[client?.carousel_style] || CAROUSEL_STYLE_LABEL.gradient

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md" onKeyDown={(e) => {
        if (e.key === 'ArrowRight') go(1)
        if (e.key === 'ArrowLeft') go(-1)
      }}>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <GalleryHorizontalEnd size={18} className="text-brand" /> Exemplo de carrossel
          </DialogTitle>
          <DialogDescription>
            {styleLabel} · assim os carrosséis deste cliente são gerados. Conteúdo ilustrativo — a IA escreve o texto real a partir do posicionamento.
          </DialogDescription>
        </DialogHeader>

        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => go(-1)}
            disabled={i === 0}
            aria-label="Slide anterior"
            className="grid size-9 shrink-0 place-items-center rounded-full border border-border bg-surface text-ink-muted transition hover:border-brand/40 hover:text-ink disabled:opacity-30"
          >
            <ChevronLeft size={18} />
          </button>

          <div className="mx-auto w-full max-w-[300px]">
            <CarouselSlide slide={slides[i]} index={i + 1} total={total} client={client} />
          </div>

          <button
            type="button"
            onClick={() => go(1)}
            disabled={i === total - 1}
            aria-label="Próximo slide"
            className="grid size-9 shrink-0 place-items-center rounded-full border border-border bg-surface text-ink-muted transition hover:border-brand/40 hover:text-ink disabled:opacity-30"
          >
            <ChevronRight size={18} />
          </button>
        </div>

        <div className="flex items-center justify-center gap-1.5">
          {slides.map((s, idx) => (
            <button
              key={idx}
              type="button"
              onClick={() => setI(idx)}
              aria-label={`Ir para o slide ${idx + 1}`}
              className={cn(
                'h-1.5 rounded-full transition-all',
                idx === i ? 'w-5 bg-brand' : 'w-1.5 bg-border hover:bg-ink-faint',
              )}
            />
          ))}
        </div>
      </DialogContent>
    </Dialog>
  )
}
