// Pick a readable foreground (near-black or white) for text/icons sitting on a
// solid brand color — agency colors can be light (yellow, lime) or dark.
export function readableOn(hex) {
  const { r, g, b } = hexToRgb(hex) || { r: 124, g: 58, b: 237 }
  // Relative luminance (sRGB) → WCAG-ish threshold.
  const lum = (0.2126 * chan(r) + 0.7152 * chan(g) + 0.0722 * chan(b))
  return lum > 0.5 ? '#18122B' : '#FFFFFF'
}

// A soft tint of the color for backgrounds (mix toward paper).
export function tint(hex, pct = 8) {
  return `color-mix(in srgb, ${hex} ${pct}%, #F5F4FB)`
}

function chan(v) {
  const s = v / 255
  return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
}

function hexToRgb(hex) {
  const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(String(hex || '').trim())
  return m ? { r: parseInt(m[1], 16), g: parseInt(m[2], 16), b: parseInt(m[3], 16) } : null
}
