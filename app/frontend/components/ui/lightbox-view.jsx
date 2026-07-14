import { lazy, Suspense, useCallback, useEffect, useRef, useState } from 'react'
import * as DialogPrimitive from '@radix-ui/react-dialog'
import { useTranslation } from 'react-i18next'
import {
  X, ChevronLeft, ChevronRight, Download, Maximize2, Minimize2, ZoomIn, ZoomOut, Play,
} from 'lucide-react'
import { attachmentKindMeta } from '@/lib/constants'
import { fileSize } from '@/lib/formatters'
import { cn } from '@/lib/utils'

const PdfSlide = lazy(() => import('./lightbox-pdf'))

const MIN_SCALE = 1
const MAX_SCALE = 5
const ZOOM_STEP = 1.45
const DOUBLE_TAP_SCALE = 2.5
const SWIPE_COMMIT = 56 // px of horizontal travel that flips to the next slide
const DISMISS_COMMIT = 120 // px of vertical travel that closes
const TAP_SLOP = 10 // movement under this is a tap, not a drag
const DOUBLE_TAP_MS = 260
const FLICK_VELOCITY = 0.45 // px/ms — a fast flick commits regardless of distance

const IDENTITY = { scale: 1, x: 0, y: 0 }
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v))
const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y)
const isZoomed = (z) => z.scale > 1.001

// ── Slides ─────────────────────────────────────────────────────────

// Zoom/pan live on the ACTIVE image only; the transform is driven by the parent
// so gestures on the stage (pinch, double-tap, wheel) reach it directly.
function ImageSlide({ item, active, zoom, mediaRef }) {
  return (
    <img
      ref={active ? mediaRef : undefined}
      data-lb-media
      src={item.url}
      alt={item.name || ''}
      draggable={false}
      className={cn(
        'max-h-full max-w-full object-contain shadow-2xl',
        active && isZoomed(zoom) ? 'cursor-grab' : 'cursor-zoom-in',
      )}
      style={active ? {
        transform: `translate3d(${zoom.x}px, ${zoom.y}px, 0) scale(${zoom.scale})`,
        transition: 'transform 0.18s cubic-bezier(0.22, 1, 0.36, 1)',
        willChange: 'transform',
      } : undefined}
    />
  )
}

// A video never autoplays (an unmuted autoplay is blocked anyway, and a muted
// one is worse than silence for UGC). A big glass play button starts it; the
// native controls take over from there. Leaving the slide pauses it.
function VideoSlide({ item, active }) {
  const { t } = useTranslation('media')
  const ref = useRef(null)
  const [playing, setPlaying] = useState(false)

  useEffect(() => {
    if (!active && ref.current) {
      ref.current.pause()
      setPlaying(false)
    }
  }, [active])

  return (
    // h-full/w-full (not max-h-full): a percentage max-height only resolves
    // against a parent with a DEFINITE height. An auto-height wrapper would let
    // the video overflow the pane and shove its native controls off-screen.
    <div data-lb-media className="relative flex h-full w-full items-center justify-center">
      {/* eslint-disable-next-line jsx-a11y/media-has-caption */}
      <video
        ref={ref}
        data-lb-nodrag
        src={item.url}
        poster={item.poster || undefined}
        controls
        playsInline
        preload="metadata"
        className="max-h-full max-w-full rounded-xl shadow-2xl"
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
      />
      {!playing && (
        // pointer-events-none on the layer, auto on the button: the overlay
        // centres the play affordance WITHOUT covering the native control strip,
        // so scrub/volume/fullscreen stay reachable before the first play.
        <div className="pointer-events-none absolute inset-0 grid place-items-center">
          <button
            type="button"
            data-lb-nodrag
            aria-label={t('play')}
            onClick={() => ref.current?.play()}
            className="pointer-events-auto grid size-20 place-items-center rounded-full bg-white/15 text-white shadow-2xl ring-1 ring-white/25 backdrop-blur-md transition hover:scale-105 hover:bg-white/25"
          >
            <Play size={30} className="ml-1" fill="currentColor" />
          </button>
        </div>
      )}
    </div>
  )
}

function AudioSlide({ item }) {
  const meta = attachmentKindMeta('audio')
  const Icon = meta.icon
  return (
    <div data-lb-media className="flex w-full max-w-md flex-col items-center gap-6 px-4">
      <div className="grid size-28 place-items-center rounded-3xl" style={{ background: `${meta.color}2A`, color: meta.color }}>
        <Icon size={48} />
      </div>
      <p className="max-w-full truncate text-center text-sm font-semibold text-white">{item.name}</p>
      {/* eslint-disable-next-line jsx-a11y/media-has-caption */}
      <audio data-lb-nodrag src={item.url} controls autoPlay className="w-full" />
    </div>
  )
}

// Formats a browser can't render inline (docx, xlsx, zip, …) — and the fallback
// when a PDF fails to parse.
function FallbackSlide({ item, message }) {
  const { t } = useTranslation('media')
  const meta = attachmentKindMeta(item.kind)
  const Icon = meta.icon
  return (
    <div data-lb-media className="flex flex-col items-center gap-5 px-6 text-center">
      <div className="grid size-28 place-items-center rounded-3xl" style={{ background: `${meta.color}2A`, color: meta.color }}>
        <Icon size={48} />
      </div>
      <div>
        <p className="max-w-xs truncate text-base font-bold text-white">{item.name}</p>
        <p className="mt-1 text-sm text-white/60">{message || t('noPreview', { label: meta.label })}</p>
        {item.byteSize ? <p className="mt-0.5 text-xs text-white/40">{fileSize(item.byteSize)}</p> : null}
      </div>
      <a
        data-lb-nodrag
        href={item.url}
        download={item.downloadName}
        target="_blank"
        rel="noreferrer"
        className="inline-flex items-center gap-2 rounded-xl bg-white px-4 py-2.5 text-sm font-semibold text-ink shadow-lg transition hover:brightness-95"
      >
        <Download size={16} /> {t('downloadFile')}
      </a>
    </div>
  )
}

function Slide({ item, active, zoom, mediaRef }) {
  const { t } = useTranslation('media')
  if (item.kind === 'image') return <ImageSlide item={item} active={active} zoom={zoom} mediaRef={mediaRef} />
  if (item.kind === 'video') return <VideoSlide item={item} active={active} />
  if (item.kind === 'audio') return <AudioSlide item={item} />
  if (item.kind === 'pdf') {
    return (
      <Suspense fallback={<SlideSpinner />}>
        {/* A PDF that pdf.js can't parse degrades to the download card. */}
        <PdfSlide item={item} fallback={<FallbackSlide item={item} message={t('pdfError')} />} />
      </Suspense>
    )
  }
  return <FallbackSlide item={item} />
}

function SlideSpinner() {
  return <div className="size-10 animate-spin rounded-full border-2 border-white/20 border-t-white/80" />
}

// ── Chrome ─────────────────────────────────────────────────────────

function ChromeButton({ icon: Icon, label, onClick, disabled, href, download }) {
  const className = cn(
    'grid size-11 place-items-center rounded-xl text-white/80 transition hover:bg-white/15 hover:text-white',
    'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/50',
    disabled && 'pointer-events-none opacity-30',
  )
  if (href) {
    return (
      <a data-lb-nodrag href={href} download={download} target="_blank" rel="noreferrer" aria-label={label} title={label} className={className}>
        <Icon size={19} />
      </a>
    )
  }
  return (
    <button type="button" data-lb-nodrag onClick={onClick} disabled={disabled} aria-label={label} title={label} className={className}>
      <Icon size={19} />
    </button>
  )
}

function Thumb({ item, active, onClick, label }) {
  const meta = attachmentKindMeta(item.kind)
  const Icon = meta.icon
  const image = item.poster || (item.kind === 'image' ? item.url : null)

  return (
    <button
      type="button"
      data-lb-nodrag
      onClick={onClick}
      aria-label={label}
      aria-current={active}
      className={cn(
        'relative size-14 shrink-0 overflow-hidden rounded-lg bg-white/5 ring-2 transition',
        active ? 'ring-brand-bright' : 'ring-transparent opacity-55 hover:opacity-100',
      )}
    >
      {image ? (
        <img src={image} alt="" className="size-full object-cover" loading="lazy" />
      ) : item.kind === 'video' ? (
        <>
          {/* #t=0.1 paints the first frame without downloading (or playing) the clip. */}
          <video src={`${item.url}#t=0.1`} muted playsInline preload="metadata" className="size-full object-cover" />
          <span className="absolute inset-0 grid place-items-center bg-black/25 text-white">
            <Play size={14} fill="currentColor" />
          </span>
        </>
      ) : (
        <span className="grid size-full place-items-center" style={{ background: `${meta.color}2A`, color: meta.color }}>
          <Icon size={18} />
        </span>
      )}
    </button>
  )
}

// ── The lightbox ───────────────────────────────────────────────────

export default function LightboxView({ items, initialIndex = 0, onClose }) {
  const { t } = useTranslation('media')
  const rootRef = useRef(null)
  const stageRef = useRef(null)
  const mediaRef = useRef(null) // the active image element (zoom bounds)
  const railRef = useRef(null)

  const [index, setIndex] = useState(() => clamp(initialIndex, 0, Math.max(0, items.length - 1)))
  const [chrome, setChrome] = useState(true)
  const [zoom, setZoom] = useState(IDENTITY)
  const [drag, setDrag] = useState(null) // { dx, dy } while a gesture is live
  const [fullscreen, setFullscreen] = useState(false)

  const count = items.length
  const item = items[index]
  const zoomable = item?.kind === 'image'
  const zoomedIn = isZoomed(zoom)

  // Gesture state lives in a ref: it changes on every pointer event and must not
  // drive re-renders (only the resulting transform does).
  const gesture = useRef({ pointers: new Map(), mode: null, start: null, pinch: null, lastTap: 0, tapTimer: null })
  // Mirrors for handlers that read the latest value without re-subscribing.
  const zoomRef = useRef(zoom)
  zoomRef.current = zoom
  const zoomableRef = useRef(zoomable)
  zoomableRef.current = zoomable

  const go = useCallback((delta) => setIndex((i) => clamp(i + delta, 0, count - 1)), [count])

  // A new slide always starts unzoomed.
  useEffect(() => { setZoom(IDENTITY) }, [index])

  // Keep the active thumbnail in view as the slide changes.
  useEffect(() => {
    railRef.current?.querySelector('[aria-current="true"]')?.scrollIntoView({ block: 'nearest', inline: 'center', behavior: 'smooth' })
  }, [index])

  // Zoom to an absolute scale while pinning the anchor point (cursor / pinch
  // midpoint / tap) to the same screen position. Scale is applied from the
  // element's center, so an anchor at screen `q` sits at image offset
  // (q - center - t) / s; solving for the post-zoom translation keeps it still.
  const zoomTo = useCallback((resolve, anchorX, anchorY) => {
    setZoom((z) => {
      const stage = stageRef.current
      if (!stage) return z
      const next = clamp(typeof resolve === 'function' ? resolve(z.scale) : resolve, MIN_SCALE, MAX_SCALE)
      if (next <= 1.001) return IDENTITY

      const rect = stage.getBoundingClientRect()
      const cx = rect.left + rect.width / 2
      const cy = rect.top + rect.height / 2
      const px = (anchorX ?? cx) - cx
      const py = (anchorY ?? cy) - cy
      let x = px - ((px - z.x) / z.scale) * next
      let y = py - ((py - z.y) / z.scale) * next

      // Never pan past the image's own edges. offsetWidth/Height are the
      // layout (contain-fitted) size — the transform doesn't affect them.
      const el = mediaRef.current
      if (el) {
        const maxX = Math.max(0, (el.offsetWidth * next - rect.width) / 2)
        const maxY = Math.max(0, (el.offsetHeight * next - rect.height) / 2)
        x = clamp(x, -maxX, maxX)
        y = clamp(y, -maxY, maxY)
      }
      return { scale: next, x, y }
    })
  }, [])

  const panTo = useCallback((x, y, scale) => {
    const el = mediaRef.current
    const stage = stageRef.current
    if (!el || !stage) return
    const maxX = Math.max(0, (el.offsetWidth * scale - stage.clientWidth) / 2)
    const maxY = Math.max(0, (el.offsetHeight * scale - stage.clientHeight) / 2)
    setZoom({ scale, x: clamp(x, -maxX, maxX), y: clamp(y, -maxY, maxY) })
  }, [])

  const toggleFullscreen = useCallback(() => {
    if (document.fullscreenElement) document.exitFullscreen?.()
    else rootRef.current?.requestFullscreen?.().catch(() => {})
  }, [])

  useEffect(() => {
    const sync = () => setFullscreen(!!document.fullscreenElement)
    document.addEventListener('fullscreenchange', sync)
    return () => {
      document.removeEventListener('fullscreenchange', sync)
      if (document.fullscreenElement) document.exitFullscreen?.().catch(() => {})
    }
  }, [])

  useEffect(() => {
    const onKey = (e) => {
      if (e.key === 'ArrowRight') { e.preventDefault(); go(1) }
      else if (e.key === 'ArrowLeft') { e.preventDefault(); go(-1) }
      else if (e.key === '+' || e.key === '=') { if (zoomableRef.current) zoomTo((s) => s * ZOOM_STEP) }
      else if (e.key === '-' || e.key === '_') { if (zoomableRef.current) zoomTo((s) => s / ZOOM_STEP) }
      else if (e.key === '0') setZoom(IDENTITY)
      else if (e.key === 'f' || e.key === 'F') toggleFullscreen()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [go, zoomTo, toggleFullscreen])

  // Wheel-to-zoom must preventDefault, so it can't ride React's passive listener.
  useEffect(() => {
    const el = stageRef.current
    if (!el) return undefined
    const onWheel = (e) => {
      if (!zoomableRef.current) return
      e.preventDefault()
      zoomTo((s) => s * (e.deltaY < 0 ? 1.18 : 1 / 1.18), e.clientX, e.clientY)
    }
    el.addEventListener('wheel', onWheel, { passive: false })
    return () => el.removeEventListener('wheel', onWheel)
  }, [zoomTo])

  useEffect(() => () => clearTimeout(gesture.current.tapTimer), [])

  // ── Pointer gestures: swipe · pinch · pan · drag-to-dismiss · tap ──

  const onPointerDown = (e) => {
    // Native controls (video/audio scrubbers, buttons, links) own their pointers.
    if (e.target.closest?.('[data-lb-nodrag]')) return
    const g = gesture.current
    g.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY })
    e.currentTarget.setPointerCapture?.(e.pointerId)

    if (g.pointers.size === 1) {
      g.mode = 'idle' // axis is undecided until the pointer clears TAP_SLOP
      g.start = {
        x: e.clientX,
        y: e.clientY,
        t: performance.now(),
        zoom: zoomRef.current,
        onMedia: !!e.target.closest?.('[data-lb-media]'),
      }
    } else if (g.pointers.size === 2) {
      const [a, b] = [...g.pointers.values()]
      g.mode = 'pinch'
      g.pinch = { dist: distance(a, b), scale: zoomRef.current.scale, cx: (a.x + b.x) / 2, cy: (a.y + b.y) / 2 }
      setDrag(null)
    }
  }

  const onPointerMove = (e) => {
    const g = gesture.current
    if (!g.pointers.has(e.pointerId)) return
    g.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY })

    if (g.mode === 'pinch') {
      if (g.pointers.size < 2 || !zoomableRef.current) return
      const [a, b] = [...g.pointers.values()]
      zoomTo((g.pinch.scale * distance(a, b)) / (g.pinch.dist || 1), g.pinch.cx, g.pinch.cy)
      return
    }

    const start = g.start
    if (!start) return
    const dx = e.clientX - start.x
    const dy = e.clientY - start.y

    // Already zoomed in → the drag pans the image instead of moving the deck.
    if (isZoomed(start.zoom)) {
      g.mode = 'pan'
      panTo(start.zoom.x + dx, start.zoom.y + dy, start.zoom.scale)
      return
    }

    if (g.mode === 'idle') {
      if (Math.abs(dx) < TAP_SLOP && Math.abs(dy) < TAP_SLOP) return
      g.mode = Math.abs(dx) > Math.abs(dy) ? 'swipe' : 'dismiss'
    }

    if (g.mode === 'swipe') {
      // Rubber-band at the ends of the deck so the edge is felt, not hit.
      const atStart = index === 0 && dx > 0
      const atEnd = index === count - 1 && dx < 0
      setDrag({ dx: atStart || atEnd ? dx * 0.35 : dx, dy: 0 })
    } else if (g.mode === 'dismiss') {
      setDrag({ dx: 0, dy })
    }
  }

  const endGesture = (e, cancelled = false) => {
    const g = gesture.current
    if (!g.pointers.has(e.pointerId)) return
    g.pointers.delete(e.pointerId)
    e.currentTarget.releasePointerCapture?.(e.pointerId)

    if (g.mode === 'pinch') {
      // Lifting one finger mid-pinch hands the gesture back to a one-finger pan.
      if (g.pointers.size === 1) {
        const [remaining] = [...g.pointers.values()]
        g.mode = 'idle'
        g.start = { x: remaining.x, y: remaining.y, t: performance.now(), zoom: zoomRef.current, onMedia: true }
      } else if (g.pointers.size === 0) {
        g.mode = null
      }
      return
    }

    const { mode, start } = g
    g.mode = null
    setDrag(null)
    if (!start || cancelled) return

    const dx = e.clientX - start.x
    const dy = e.clientY - start.y
    const elapsed = Math.max(1, performance.now() - start.t)

    if (mode === 'swipe') {
      if (Math.abs(dx) > SWIPE_COMMIT || Math.abs(dx / elapsed) > FLICK_VELOCITY) go(dx < 0 ? 1 : -1)
      return
    }
    if (mode === 'dismiss') {
      if (Math.abs(dy) > DISMISS_COMMIT || Math.abs(dy / elapsed) > FLICK_VELOCITY) onClose()
      return
    }
    if (mode === 'pan') return

    // A tap. Off the media (the void around it) closes — that's the backdrop.
    if (Math.abs(dx) > TAP_SLOP || Math.abs(dy) > TAP_SLOP) return
    if (!start.onMedia) { onClose(); return }

    // On the media: double-tap zooms, single tap toggles the chrome. The single
    // tap waits out the double-tap window so the two never both fire.
    const now = performance.now()
    if (now - g.lastTap < DOUBLE_TAP_MS) {
      clearTimeout(g.tapTimer)
      g.lastTap = 0
      if (zoomableRef.current) zoomTo((s) => (s > 1.001 ? 1 : DOUBLE_TAP_SCALE), e.clientX, e.clientY)
      return
    }
    g.lastTap = now
    clearTimeout(g.tapTimer)
    g.tapTimer = setTimeout(() => setChrome((c) => !c), DOUBLE_TAP_MS)
  }

  // ── Render ────────────────────────────────────────────────────────

  const dismissing = Math.abs(drag?.dy || 0)
  const dismissProgress = Math.min(1, dismissing / 320)
  // The track is exactly one stage wide and every pane is a full track wide, so
  // a percentage translate steps by exactly one slide — no measuring, and no
  // first-paint window where the panes are laid out at the wrong width. The live
  // drag rides along in px on top of it.
  const trackOffset = `calc(${-index * 100}% + ${drag?.dx || 0}px)`

  return (
    <DialogPrimitive.Root open onOpenChange={(next) => { if (!next) onClose() }}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Content
          ref={rootRef}
          data-lightbox-root
          onOpenAutoFocus={(e) => e.preventDefault()}
          // z-200: the lightbox opens from inside dialogs (the scenes editor, the
          // studio) and must sit above them. pointer-events-auto!: Radix pins
          // pointer-events:none on <body> while any dialog is open.
          // The entrance animation (.ag-lightbox) owns this element's opacity, so
          // the drag-to-dismiss fade has to live on the layer below — an animation
          // with `both` outranks an inline style and would freeze it at 1.
          className="ag-lightbox fixed inset-0 z-200 select-none overflow-hidden text-white pointer-events-auto! focus:outline-none"
        >
          <DialogPrimitive.Title className="sr-only">{item?.name || t('title')}</DialogPrimitive.Title>
          <DialogPrimitive.Description className="sr-only">{t('description')}</DialogPrimitive.Description>

          <div
            className="absolute inset-0 flex flex-col"
            style={{
              background: 'radial-gradient(130% 100% at 50% 0%, #1B1136 0%, #0B0716 62%)',
              opacity: 1 - dismissProgress * 0.55,
            }}
          >
            {/* Header — name + counter left, tools right. Sits over the stage on a
                scrim so it stays legible against any media. */}
            <header
              className={cn(
                'absolute inset-x-0 top-0 z-20 flex items-start justify-between gap-3 bg-linear-to-b from-black/70 to-transparent p-3 pb-10 transition-opacity duration-200 sm:p-4 sm:pb-12',
                'pt-[calc(env(safe-area-inset-top)+0.75rem)]',
                chrome ? 'opacity-100' : 'pointer-events-none opacity-0',
              )}
            >
              <div className="min-w-0 flex-1 pt-2 pl-1">
                {item?.name && <p className="truncate font-display text-sm font-bold sm:text-base">{item.name}</p>}
                {count > 1 && (
                  <p className="mt-0.5 text-xs font-medium text-white/55">
                    {t('counter', { current: index + 1, total: count })}
                  </p>
                )}
              </div>

              <div className="flex shrink-0 items-center gap-0.5 rounded-2xl bg-white/8 p-1 ring-1 ring-white/10 backdrop-blur-md">
                {/* Zoom buttons are a desktop nicety — on touch, pinch and
                    double-tap do this better and the bar space is worth more. */}
                {zoomable && (
                  <span className="hidden sm:contents">
                    <ChromeButton icon={ZoomOut} label={t('zoomOut')} disabled={!zoomedIn} onClick={() => zoomTo((s) => s / ZOOM_STEP)} />
                    <ChromeButton icon={ZoomIn} label={t('zoomIn')} disabled={zoom.scale >= MAX_SCALE} onClick={() => zoomTo((s) => s * ZOOM_STEP)} />
                  </span>
                )}
                <span className="hidden sm:contents">
                  <ChromeButton
                    icon={fullscreen ? Minimize2 : Maximize2}
                    label={fullscreen ? t('exitFullscreen') : t('fullscreen')}
                    onClick={toggleFullscreen}
                  />
                </span>
                <ChromeButton icon={Download} label={t('download')} href={item?.url} download={item?.downloadName} />
                <ChromeButton icon={X} label={t('close')} onClick={onClose} />
              </div>
            </header>

            {/* Stage — owns every gesture. touch-none hands the browser's native
                pan/zoom back to us so pinch and swipe don't scroll the page. */}
            <div
              ref={stageRef}
              className="relative min-h-0 flex-1 touch-none overflow-hidden"
              onPointerDown={onPointerDown}
              onPointerMove={onPointerMove}
              onPointerUp={endGesture}
              onPointerCancel={(e) => endGesture(e, true)}
            >
              {/* The deck: every slide is one full stage wide, laid out left to
                  right and moved as one. The panes overflow the track by design —
                  the stage clips them. */}
              <div
                className="flex h-full w-full"
                style={{
                  transform: `translate3d(${trackOffset}, ${drag?.dy || 0}px, 0) scale(${1 - dismissProgress * 0.12})`,
                  transition: drag ? 'none' : 'transform 0.34s cubic-bezier(0.22, 1, 0.36, 1)',
                  willChange: 'transform',
                }}
              >
                {items.map((media, i) => (
                  <div
                    key={media.id ?? i}
                    className="flex h-full w-full shrink-0 items-center justify-center px-3 py-20 sm:px-16 sm:py-24"
                  >
                    {/* Only the current slide and its neighbours mount — a 30-slide
                        carousel must not load 30 videos. */}
                    {Math.abs(i - index) <= 1 && (
                      <Slide item={media} active={i === index} zoom={zoom} mediaRef={mediaRef} />
                    )}
                  </div>
                ))}
              </div>

              {/* Desktop arrows. On touch the swipe is the affordance. */}
              {count > 1 && (
                <>
                  <button
                    type="button"
                    data-lb-nodrag
                    onClick={() => go(-1)}
                    disabled={index === 0}
                    aria-label={t('previous')}
                    className={cn(
                      'absolute left-4 top-1/2 z-10 hidden -translate-y-1/2 place-items-center rounded-full bg-white/10 p-3 text-white ring-1 ring-white/15 backdrop-blur-md transition hover:bg-white/20 disabled:pointer-events-none disabled:opacity-0 sm:grid',
                      !chrome && 'opacity-0',
                    )}
                  >
                    <ChevronLeft size={22} />
                  </button>
                  <button
                    type="button"
                    data-lb-nodrag
                    onClick={() => go(1)}
                    disabled={index === count - 1}
                    aria-label={t('next')}
                    className={cn(
                      'absolute right-4 top-1/2 z-10 hidden -translate-y-1/2 place-items-center rounded-full bg-white/10 p-3 text-white ring-1 ring-white/15 backdrop-blur-md transition hover:bg-white/20 disabled:pointer-events-none disabled:opacity-0 sm:grid',
                      !chrome && 'opacity-0',
                    )}
                  >
                    <ChevronRight size={22} />
                  </button>
                </>
              )}
            </div>

            {/* Footer — caption + the filmstrip. */}
            <footer
              className={cn(
                'absolute inset-x-0 bottom-0 z-20 bg-linear-to-t from-black/75 to-transparent px-3 pt-12 transition-opacity duration-200 sm:px-4',
                'pb-[calc(env(safe-area-inset-bottom)+0.75rem)]',
                chrome ? 'opacity-100' : 'pointer-events-none opacity-0',
              )}
            >
              {item?.caption && (
                <p className="mx-auto mb-3 line-clamp-2 max-w-2xl text-center text-[13px] leading-relaxed text-white/75">
                  {item.caption}
                </p>
              )}
              {count > 1 && (
                <div
                  ref={railRef}
                  className="scrollbar-subtle mx-auto flex max-w-full snap-x items-center justify-start gap-2 overflow-x-auto pb-1 sm:justify-center"
                >
                  {items.map((media, i) => (
                    <Thumb
                      key={media.id ?? i}
                      item={media}
                      active={i === index}
                      onClick={() => setIndex(i)}
                      label={t('goToSlide', { index: i + 1 })}
                    />
                  ))}
                </div>
              )}
            </footer>
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  )
}
