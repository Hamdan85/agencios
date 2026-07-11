import { useEffect, useRef } from 'react'
import { useTranslation } from 'react-i18next'

const WIDTH = 600
const HEIGHT = 200
const GROUND_Y = HEIGHT - 32
const GRAVITY = 0.0028
const JUMP_VELOCITY = -0.95
const BASE_SPEED = 0.32
const HIGHSCORE_KEY = 'agencios-dino-highscore'
const OBSTACLE_COLORS = ['#8B5CF6', '#EC4899', '#0EA5E9', '#F59E0B']

// A Chrome-offline-style runner, reskinned for agencios. Same physics/visuals
// as the vanilla version at public/errors/dino.js — kept separate because that
// one runs on static error pages outside the Vite bundle.
export function DinoRunner() {
  const { t } = useTranslation('errors')
  const canvasRef = useRef(null)
  const hintRef = useRef(null)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')

    let state = 'idle' // idle | running | over
    let highscore = 0
    try { highscore = parseInt(localStorage.getItem(HIGHSCORE_KEY), 10) || 0 } catch { highscore = 0 }

    const runner = { x: 46, y: GROUND_Y - 34, w: 30, h: 34, vy: 0, onGround: true, legPhase: 0 }
    let obstacles = []
    let speed = BASE_SPEED
    let distance = 0
    let lastSpawnAt = 0
    let nextSpawnIn = 900
    let lastFrameAt = null
    let rafId = null

    function resetGame() {
      runner.y = GROUND_Y - runner.h
      runner.vy = 0
      runner.onGround = true
      obstacles = []
      speed = BASE_SPEED
      distance = 0
      lastSpawnAt = 0
      nextSpawnIn = 900
      lastFrameAt = null
    }

    function jump() {
      if (state === 'idle') {
        state = 'running'
        resetGame()
        rafId = requestAnimationFrame(loop)
      } else if (state === 'over') {
        state = 'running'
        resetGame()
      } else if (state === 'running' && runner.onGround) {
        runner.vy = JUMP_VELOCITY
        runner.onGround = false
      }
    }

    function spawnObstacle() {
      const h = 22 + Math.random() * 22
      const w = 14 + Math.random() * 10
      obstacles.push({ x: WIDTH + w, y: GROUND_Y - h, w, h, color: OBSTACLE_COLORS[Math.floor(Math.random() * OBSTACLE_COLORS.length)] })
    }

    function rectsOverlap(a, b) {
      return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
    }

    function drawGround() {
      ctx.strokeStyle = 'rgba(255,255,255,0.18)'
      ctx.lineWidth = 2
      ctx.beginPath()
      ctx.moveTo(0, GROUND_Y + 1)
      ctx.lineTo(WIDTH, GROUND_Y + 1)
      ctx.stroke()
    }

    function drawRunner() {
      const bob = runner.onGround ? Math.sin(runner.legPhase) * 2 : 0
      const x = runner.x
      const y = runner.y + bob
      ctx.fillStyle = '#F5F4FB'
      ctx.beginPath()
      ctx.roundRect ? ctx.roundRect(x, y, runner.w, runner.h - 8, 6) : ctx.rect(x, y, runner.w, runner.h - 8)
      ctx.fill()
      ctx.beginPath()
      ctx.roundRect ? ctx.roundRect(x + runner.w - 12, y - 8, 16, 14, 4) : ctx.rect(x + runner.w - 12, y - 8, 16, 14)
      ctx.fill()
      ctx.fillStyle = '#110A24'
      ctx.fillRect(x + runner.w - 4, y - 4, 3, 3)
      ctx.fillStyle = '#F5F4FB'
      const legOffset = runner.onGround ? Math.sin(runner.legPhase) * 6 : 0
      ctx.fillRect(x + 4, y + runner.h - 8, 6, 8 + legOffset)
      ctx.fillRect(x + runner.w - 14, y + runner.h - 8, 6, 8 - legOffset)
    }

    function drawObstacle(o) {
      ctx.fillStyle = o.color
      ctx.beginPath()
      ctx.roundRect ? ctx.roundRect(o.x, o.y, o.w, o.h, 4) : ctx.rect(o.x, o.y, o.w, o.h)
      ctx.fill()
    }

    function drawScore() {
      const score = Math.floor(distance / 10)
      ctx.fillStyle = 'rgba(255,255,255,0.65)'
      ctx.font = '600 13px Inter, ui-sans-serif, sans-serif'
      ctx.textAlign = 'right'
      let label = String(score).padStart(5, '0')
      if (highscore > 0) label = `HI ${String(highscore).padStart(5, '0')}   ${label}`
      ctx.fillText(label, WIDTH - 10, 22)
      return score
    }

    function drawCenteredMessage(lines) {
      ctx.fillStyle = 'rgba(255,255,255,0.9)'
      ctx.textAlign = 'center'
      ctx.font = '700 16px Sora, ui-sans-serif, sans-serif'
      ctx.fillText(lines[0], WIDTH / 2, HEIGHT / 2 - (lines[1] ? 8 : 0))
      if (lines[1]) {
        ctx.font = '400 12px Inter, ui-sans-serif, sans-serif'
        ctx.fillStyle = 'rgba(255,255,255,0.6)'
        ctx.fillText(lines[1], WIDTH / 2, HEIGHT / 2 + 14)
      }
    }

    function render(score) {
      ctx.clearRect(0, 0, WIDTH, HEIGHT)
      drawGround()
      drawRunner()
      obstacles.forEach(drawObstacle)
      drawScore()
      if (state === 'idle') drawCenteredMessage([t('dino.start')])
      else if (state === 'over') drawCenteredMessage([t('dino.gameOver', { score }), t('dino.retry')])
    }

    function loop(timestamp) {
      if (state !== 'running') return
      if (lastFrameAt == null) lastFrameAt = timestamp
      const dt = Math.min(timestamp - lastFrameAt, 48)
      lastFrameAt = timestamp

      distance += dt * speed
      speed = BASE_SPEED + Math.min(distance / 40000, 0.35)
      runner.legPhase += dt * 0.02

      runner.vy += GRAVITY * dt
      runner.y += runner.vy * dt
      if (runner.y >= GROUND_Y - runner.h) {
        runner.y = GROUND_Y - runner.h
        runner.vy = 0
        runner.onGround = true
      }

      lastSpawnAt += dt
      if (lastSpawnAt > nextSpawnIn) {
        spawnObstacle()
        lastSpawnAt = 0
        nextSpawnIn = Math.max(700 + Math.random() * 900 - Math.min(distance / 100, 300), 420)
      }

      const runnerBox = { x: runner.x + 4, y: runner.y, w: runner.w - 8, h: runner.h - 4 }
      for (let i = obstacles.length - 1; i >= 0; i--) {
        obstacles[i].x -= speed * dt
        if (rectsOverlap(runnerBox, obstacles[i])) {
          state = 'over'
          const finalScore = Math.floor(distance / 10)
          if (finalScore > highscore) {
            highscore = finalScore
            try { localStorage.setItem(HIGHSCORE_KEY, String(highscore)) } catch { /* ignore */ }
          }
        }
        if (obstacles[i].x + obstacles[i].w < 0) obstacles.splice(i, 1)
      }

      render(Math.floor(distance / 10))
      if (state === 'running') rafId = requestAnimationFrame(loop)
      else render(Math.floor(distance / 10))
    }

    function handleKeydown(e) {
      if (e.code === 'Space' || e.code === 'ArrowUp') {
        e.preventDefault()
        jump()
      }
    }
    function handlePointerdown(e) {
      e.preventDefault()
      jump()
    }
    function handleVisibility() {
      if (document.hidden && state === 'running') state = 'over'
    }

    document.addEventListener('keydown', handleKeydown)
    canvas.addEventListener('pointerdown', handlePointerdown)
    document.addEventListener('visibilitychange', handleVisibility)
    if (hintRef.current) hintRef.current.textContent = t('dino.hint')

    render(0)

    return () => {
      if (rafId) cancelAnimationFrame(rafId)
      document.removeEventListener('keydown', handleKeydown)
      canvas.removeEventListener('pointerdown', handlePointerdown)
      document.removeEventListener('visibilitychange', handleVisibility)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div className="mt-6 grid w-full justify-items-center gap-2">
      <canvas
        ref={canvasRef}
        width={WIDTH}
        height={HEIGHT}
        className="w-full max-w-xl cursor-pointer rounded-2xl border border-white/10 bg-white/5"
        style={{ aspectRatio: `${WIDTH} / ${HEIGHT}` }}
      />
      <p ref={hintRef} className="text-xs text-white/40">{t('dino.loading')}</p>
    </div>
  )
}

export default DinoRunner
