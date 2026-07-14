import { useEffect, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import i18n from '@/i18n'
import { ChevronLeft, ChevronRight, GalleryHorizontalEnd } from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from '@/components/ui/dialog'
import { cn } from '@/lib/utils'
import { CAROUSEL_STYLE_LABEL } from './positioningFields'
import { carouselTheme } from './carouselTheme'

// The generated slide is authored on a 1080px-wide canvas (see the backend
// Creatives::CarouselSlideTemplate). We reproduce every measurement faithfully by
// expressing it as a fraction of the container width via CSS container-query
// units — so this on-screen slide is a true 1:1 miniature of the real output,
// not an approximation.
const DESIGN_W = 1080
const u = (px) => `${((px / DESIGN_W) * 100).toFixed(4)}cqw`

function initialsOf(name) {
  const parts = String(name || '').split(/\s+/).filter(Boolean).slice(0, 2)
  return parts.map((w) => w[0]).join('').toUpperCase() || '•'
}

// One faithful carousel slide — the exact layout the headless renderer produces,
// themed with the client's real brand identity (colors, @handle, avatar, logo)
// and carousel style (gradient / white / image).
export function CarouselSlide({ slide, index, total, client, className }) {
  const { t } = useTranslation('clients')
  const style = client?.carousel_style || 'gradient'
  const imageUrl = style === 'image' ? client?.carousel_background_url : null
  const {
    hasImage, white, secondary, accent, onAccent, ink, background: bg, scrim,
    textShadow: shadow, headlineShadow: hlShadow,
  } = carouselTheme({
    style,
    primary: client?.brand_primary_color,
    secondary: client?.brand_secondary_color,
    imageUrl,
    palette: client?.carousel_image_palette,
  })

  const isHook = index === 1
  const isCta = index === total
  const hl = isHook ? 92 : isCta ? 84 : 72

  const handle = String(client?.default_handle || '').replace(/^@/, '')

  return (
    <div
      className={cn('relative overflow-hidden rounded-xl ring-1 ring-black/5', className)}
      style={{ containerType: 'inline-size', aspectRatio: '4 / 5', width: '100%', background: bg, color: ink }}
    >
      {hasImage && (
        <img src={imageUrl} alt="" className="absolute inset-0 size-full object-cover" />
      )}
      {scrim && (
        <div className="absolute inset-0" style={{ background: scrim.color, opacity: scrim.opacity }} />
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
                style={{ width: u(96), height: u(96), background: accent, color: onAccent, fontSize: u(40) }}
              >
                {initialsOf(client?.name)}
              </div>
            )}
            <div className="flex flex-col" style={{ lineHeight: 1.15 }}>
              <span className="font-extrabold" style={{ fontSize: u(36), textShadow: shadow }}>{client?.name || t('example.brandFallback')}</span>
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
              style={{ fontSize: u(30), letterSpacing: u(2), color: accent, textShadow: shadow }}
            >
              {t('example.nextStep')}
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
            style={{ fontSize: u(30), opacity: 0.85, borderTop: `${u(4)} solid ${accent}`, paddingTop: u(16), textShadow: shadow }}
          >
            {isCta ? t('example.saveShare') : t('example.swipe')}
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
  const brand = client?.name || i18n.t('clients:example.theBrand')
  const pillars = (Array.isArray(pos.content_pillars) ? pos.content_pillars : []).map((p) => String(p || '').trim()).filter(Boolean)
  const oneLiner = String(pos.one_liner || '').trim()
  const value = String(pos.value_proposition || '').trim()
  const pain = String(pos.audience_pain || '').trim()

  const clip = (s, n = 60) => (s.length <= n ? s : `${s.slice(0, n - 1).trimEnd()}…`)
  const cap = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s)

  const points = (pillars.length ? pillars : [
    i18n.t('clients:example.point1'),
    i18n.t('clients:example.point2'),
    i18n.t('clients:example.point3'),
  ]).slice(0, 4)

  const hook = {
    role: 'hook',
    headline: clip(pain ? cap(pain) : i18n.t('clients:example.hookHeadline', { brand })),
    body: clip(oneLiner || value || i18n.t('clients:example.hookBody'), 90),
  }
  const valueSlides = points.map((p) => ({ role: 'value', headline: clip(cap(p)) }))
  const cta = {
    role: 'cta',
    headline: i18n.t('clients:example.ctaHeadline'),
    body: clip(client?.default_handle ? i18n.t('clients:example.ctaBodyHandle', { handle: String(client.default_handle).replace(/^@/, '') }) : i18n.t('clients:example.ctaBody'), 90),
  }

  return [hook, ...valueSlides, cta]
}

// A full, paged example carousel — exactly the format generated for this client,
// so the team can see the real output before generating anything. Purely
// illustrative (the copy is example content; the AI writes the real words).
export function CarouselExampleDialog({ client, open, onOpenChange }) {
  const { t } = useTranslation('clients')
  const slides = buildExampleSlides(client)
  const total = slides.length
  const [i, setI] = useState(0)

  useEffect(() => { if (open) setI(0) }, [open])

  const go = (n) => setI((cur) => Math.min(total - 1, Math.max(0, cur + n)))

  // Mobile shows every slide in a swipeable snap rail (see below), so the active dot
  // follows the scroll position instead of a click.
  const railRef = useRef(null)
  const onRailScroll = (e) => {
    const el = e.currentTarget
    setI(Math.round(el.scrollLeft / el.clientWidth))
  }
  const scrollToSlide = (idx) => {
    setI(idx)
    railRef.current?.scrollTo({ left: idx * railRef.current.clientWidth, behavior: 'smooth' })
  }
  const styleLabel = CAROUSEL_STYLE_LABEL[client?.carousel_style] || CAROUSEL_STYLE_LABEL.gradient

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md" onKeyDown={(e) => {
        if (e.key === 'ArrowRight') go(1)
        if (e.key === 'ArrowLeft') go(-1)
      }}>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <GalleryHorizontalEnd size={18} className="text-brand" /> {t('example.dialogTitle')}
          </DialogTitle>
          <DialogDescription>
            {t('example.dialogDescription', { style: styleLabel })}
          </DialogDescription>
        </DialogHeader>

        {/* Mobile: swipe. The two 36px arrows ate 25% of a 320px row — of the very preview
            they frame — and swiping is the native gesture anyway. Render every slide in a
            snap rail so the full width goes to the artwork. */}
        <div
          ref={railRef}
          onScroll={onRailScroll}
          className="no-scrollbar -mx-5 flex snap-x snap-mandatory overflow-x-auto overscroll-x-contain px-5 sm:hidden"
        >
          {slides.map((s, idx) => (
            <div key={idx} className="w-full shrink-0 snap-center">
              <CarouselSlide slide={s} index={idx + 1} total={total} client={client} />
            </div>
          ))}
        </div>

        {/* Desktop: arrows + one slide (a cursor makes 36px targets fine). */}
        <div className="hidden items-center gap-2 sm:flex">
          <button
            type="button"
            onClick={() => go(-1)}
            disabled={i === 0}
            aria-label={t('example.prevSlide')}
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
            aria-label={t('example.nextSlide')}
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
              onClick={() => scrollToSlide(idx)}
              aria-label={t('example.goToSlide', { n: idx + 1 })}
              className={cn(
                // The dot is 6px; `before:` gives it a 44px invisible hit area.
                'relative h-1.5 rounded-full transition-all before:absolute before:-inset-2.5 before:content-[""]',
                idx === i ? 'w-5 bg-brand' : 'w-1.5 bg-border hover:bg-ink-faint',
              )}
            />
          ))}
        </div>
      </DialogContent>
    </Dialog>
  )
}
