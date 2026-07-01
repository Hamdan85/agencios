// Chrome-offline-style runner, reskinned for agencios error pages.
// Self-contained: no build step, no dependencies. Mounts into #dino-canvas.
(function () {
  var canvas = document.getElementById('dino-canvas')
  if (!canvas || !canvas.getContext) return
  var hint = document.getElementById('dino-hint')
  var ctx = canvas.getContext('2d')

  var WIDTH = canvas.width
  var HEIGHT = canvas.height
  var GROUND_Y = HEIGHT - 32

  var GRAVITY = 0.0028
  var JUMP_VELOCITY = -0.95
  var BASE_SPEED = 0.32
  var HIGHSCORE_KEY = 'agencios-dino-highscore'

  var OBSTACLE_COLORS = ['#8B5CF6', '#EC4899', '#0EA5E9', '#F59E0B']

  var state = 'idle' // idle | running | over
  var runner = { x: 46, y: GROUND_Y - 34, w: 30, h: 34, vy: 0, onGround: true, legPhase: 0 }
  var obstacles = []
  var speed = BASE_SPEED
  var distance = 0
  var lastSpawnAt = 0
  var nextSpawnIn = 900
  var lastFrameAt = null
  var highscore = 0

  try { highscore = parseInt(localStorage.getItem(HIGHSCORE_KEY), 10) || 0 } catch (e) { highscore = 0 }

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
      requestAnimationFrame(loop)
    } else if (state === 'over') {
      state = 'running'
      resetGame()
    } else if (state === 'running' && runner.onGround) {
      runner.vy = JUMP_VELOCITY
      runner.onGround = false
    }
  }

  function spawnObstacle() {
    var h = 22 + Math.random() * 22
    var w = 14 + Math.random() * 10
    obstacles.push({
      x: WIDTH + w,
      y: GROUND_Y - h,
      w: w,
      h: h,
      color: OBSTACLE_COLORS[Math.floor(Math.random() * OBSTACLE_COLORS.length)],
    })
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
    ctx.fillStyle = '#F5F4FB'
    var bob = runner.onGround ? Math.sin(runner.legPhase) * 2 : 0
    var x = runner.x
    var y = runner.y + bob
    // body
    ctx.beginPath()
    ctx.roundRect ? ctx.roundRect(x, y, runner.w, runner.h - 8, 6) : ctx.rect(x, y, runner.w, runner.h - 8)
    ctx.fill()
    // head
    ctx.beginPath()
    ctx.roundRect ? ctx.roundRect(x + runner.w - 12, y - 8, 16, 14, 4) : ctx.rect(x + runner.w - 12, y - 8, 16, 14)
    ctx.fill()
    // eye
    ctx.fillStyle = '#110A24'
    ctx.fillRect(x + runner.w - 4, y - 4, 3, 3)
    // legs
    ctx.fillStyle = '#F5F4FB'
    var legOffset = runner.onGround ? Math.sin(runner.legPhase) * 6 : 0
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
    var score = Math.floor(distance / 10)
    ctx.fillStyle = 'rgba(255,255,255,0.65)'
    ctx.font = '600 13px Inter, ui-sans-serif, sans-serif'
    ctx.textAlign = 'right'
    var label = String(score).padStart(5, '0')
    if (highscore > 0) label = 'HI ' + String(highscore).padStart(5, '0') + '   ' + label
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
    if (state === 'idle') {
      drawCenteredMessage(['Pressione espaço ou toque para começar'])
    } else if (state === 'over') {
      drawCenteredMessage(['Fim de jogo — pontuação ' + score, 'Pressione espaço ou toque para tentar de novo'])
    }
  }

  function loop(timestamp) {
    if (state !== 'running') return
    if (lastFrameAt == null) lastFrameAt = timestamp
    var dt = Math.min(timestamp - lastFrameAt, 48)
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
      nextSpawnIn = 700 + Math.random() * 900 - Math.min(distance / 100, 300)
      nextSpawnIn = Math.max(nextSpawnIn, 420)
    }

    var runnerBox = { x: runner.x + 4, y: runner.y, w: runner.w - 8, h: runner.h - 4 }
    for (var i = obstacles.length - 1; i >= 0; i--) {
      obstacles[i].x -= speed * dt
      if (rectsOverlap(runnerBox, obstacles[i])) {
        state = 'over'
        var finalScore = Math.floor(distance / 10)
        if (finalScore > highscore) {
          highscore = finalScore
          try { localStorage.setItem(HIGHSCORE_KEY, String(highscore)) } catch (e) {}
        }
      }
      if (obstacles[i].x + obstacles[i].w < 0) obstacles.splice(i, 1)
    }

    render(Math.floor(distance / 10))
    if (state === 'running') requestAnimationFrame(loop)
    else render(Math.floor(distance / 10))
  }

  document.addEventListener('keydown', function (e) {
    if (e.code === 'Space' || e.code === 'ArrowUp') {
      e.preventDefault()
      jump()
    }
  })
  canvas.addEventListener('pointerdown', function (e) {
    e.preventDefault()
    jump()
  })
  document.addEventListener('visibilitychange', function () {
    if (document.hidden && state === 'running') state = 'over'
  })

  if (hint) hint.textContent = 'Espaço, ↑ ou toque no jogo para pular os obstáculos'

  render(0)
})()
