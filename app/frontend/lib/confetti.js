// A tiny, dependency-free confetti burst on a throwaway full-screen canvas.
// Respects prefers-reduced-motion (no-op). Colored in the agency's brand hue.
export function burstConfetti(color = '#7C3AED') {
  if (typeof window === 'undefined') return
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return

  const canvas = document.createElement('canvas')
  canvas.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:60'
  canvas.width = window.innerWidth
  canvas.height = window.innerHeight
  document.body.appendChild(canvas)
  const ctx = canvas.getContext('2d')

  const colors = [color, '#FFFFFF', '#F59E0B', '#EC4899']
  const cx = canvas.width / 2
  const cy = canvas.height * 0.4
  const pieces = Array.from({ length: 90 }, (_, i) => ({
    x: cx, y: cy,
    vx: Math.cos((i / 90) * Math.PI * 2) * (2 + (i % 7)),
    vy: Math.sin((i / 90) * Math.PI * 2) * (2 + (i % 5)) - 4,
    size: 5 + (i % 6),
    color: colors[i % colors.length],
    rot: i, spin: (i % 5) - 2,
  }))

  let frame = 0
  const tick = () => {
    frame += 1
    ctx.clearRect(0, 0, canvas.width, canvas.height)
    pieces.forEach((p) => {
      p.vy += 0.18 // gravity
      p.x += p.vx
      p.y += p.vy
      p.rot += p.spin
      ctx.save()
      ctx.translate(p.x, p.y)
      ctx.rotate((p.rot * Math.PI) / 180)
      ctx.fillStyle = p.color
      ctx.globalAlpha = Math.max(0, 1 - frame / 80)
      ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size * 0.6)
      ctx.restore()
    })
    if (frame < 80) requestAnimationFrame(tick)
    else canvas.remove()
  }
  requestAnimationFrame(tick)
}
