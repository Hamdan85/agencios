// The single source of truth for how a carousel slide is colored on the frontend.
// It mirrors the backend Creatives::CarouselSlideTemplate rule for rule, so both
// previews (the style picker and the full example) show the real output rather
// than an approximation — and there is one place to keep in sync, not two.

const DEFAULT_PRIMARY = '#7C3AED'
const DEFAULT_SECONDARY = '#F59E0B'
const DEFAULT_INK = '#ffffff'
const WHITE_INK = '#18161d'

// Darken/lighten a #rrggbb hex — mirrors CarouselSlideTemplate#shade.
export function shade(hex, pct) {
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || '').trim())
  if (!m) return hex || DEFAULT_PRIMARY
  const n = parseInt(m[1], 16)
  const adj = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((c) =>
    Math.min(255, Math.max(0, Math.round(c + (255 * pct) / 100))),
  )
  return `#${adj.map((c) => c.toString(16).padStart(2, '0')).join('')}`
}

// Relative luminance (WCAG) — mirrors CarouselSlideTemplate#light?.
function isLight(hex) {
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || '').trim())
  if (!m) return true
  const rgb = (m[1].match(/../g) || []).map((c) => {
    const v = parseInt(c, 16) / 255
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2] > 0.4
}

// Mirrors CarouselSlideTemplate::TEXT_SHADOWS. The shadow ink is a halo, not a
// smudge: dark behind light text, light behind dark text.
const TEXT_SHADOWS = {
  none: null,
  soft: { base: '0 2px 12px', baseAlpha: 0.55, headline: '0 4px 24px', headlineAlpha: 0.65 },
  strong: { base: '0 2px 16px', baseAlpha: 0.78, headline: '0 4px 32px', headlineAlpha: 0.88 },
}
const DEFAULT_TEXT_SHADOW = 'soft'

// Resolve the theme of one slide. `palette` is the client's AI-derived
// carousel_image_palette — read ONLY by the image style, exactly as the backend
// does; gradient/white keep the brand colors. A missing/partial palette falls back
// to the brand look, so an image whose analysis hasn't landed yet still renders.
export function carouselTheme({ style, primary, secondary, imageUrl, palette }) {
  const brandPrimary = primary || DEFAULT_PRIMARY
  const brandSecondary = secondary || DEFAULT_SECONDARY
  const hasImage = style === 'image' && !!imageUrl
  const white = style === 'white' && !hasImage

  const p = palette || {}
  // Mirrors CarouselSlideTemplate#palette? — bookkeeping keys alone don't count.
  const themed = hasImage && !!(p.accent || p.text_color)

  const accent = (themed && p.accent) || brandSecondary
  const onAccent = (themed && p.on_accent) || '#ffffff'
  const ink = white ? WHITE_INK : (themed && p.text_color) || DEFAULT_INK

  const background = white
    ? '#ffffff'
    : hasImage
      ? '#2b2730' // only ever seen if the photo fails to load; the image covers it
      : `radial-gradient(120% 120% at 0% 0%, ${brandPrimary} 0%, ${shade(brandPrimary, -28)} 70%)`

  // The scrim is the last-resort lever — opacity 0 (the preferred default) keeps
  // the photo clean, so render nothing at all.
  const opacity = hasImage ? Number(p.scrim_opacity) || 0 : 0
  const scrim = opacity > 0 ? { color: p.scrim_color || '#000000', opacity } : null

  const spec = hasImage
    ? TEXT_SHADOWS[p.text_shadow] !== undefined
      ? TEXT_SHADOWS[p.text_shadow]
      : TEXT_SHADOWS[DEFAULT_TEXT_SHADOW]
    : null
  const shadowInk = isLight(ink) ? '0,0,0' : '255,255,255'
  const textShadow = spec ? `${spec.base} rgba(${shadowInk},${spec.baseAlpha})` : undefined
  const headlineShadow = spec ? `${spec.headline} rgba(${shadowInk},${spec.headlineAlpha})` : undefined

  return {
    hasImage, white, themed,
    primary: brandPrimary, secondary: brandSecondary,
    accent, onAccent, ink, background, scrim, textShadow, headlineShadow,
  }
}
