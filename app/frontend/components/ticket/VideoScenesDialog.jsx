import { useEffect, useMemo, useRef, useState, lazy, Suspense } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import {
  Film, Loader2, RefreshCw, Check, AlertCircle, Sparkles, MessageSquare,
  Play, Pause, X, ArrowUpCircle, Download, ImagePlus, TriangleAlert, Coins, Pencil,
  Clapperboard, Boxes, UserRound, Image as ImageIcon, Music, Wand2,
  Trash2, Plus, Upload, Library, Maximize2,
} from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from '@/components/ui/dialog'
import { Popover, PopoverTrigger, PopoverContent } from '@/components/ui/popover'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { SectionLabel } from '@/components/ui/section-label'
import { Textarea } from '@/components/ui/input'
import { Spinner, InlineSpinner, Skeleton, EmptyState } from '@/components/ui/feedback'
import { Bubble, TypingDots, ChatComposer } from '@/components/ui/chat'
import { Markdown } from '@/components/ui/markdown'
import { useConfirm } from '@/components/ui/confirm-dialog'
import {
  useVideoScenes, useVideoChat, useFinalizeVideo, useCredits,
  useVideoAssets, useRegenerateAsset, useAddAsset, useRemoveAsset, useAssetLibrary,
} from '@/hooks/useData'
import { uploadsApi } from '@/api'
import { cn } from '@/lib/utils'
import i18n from '@/i18n'
import { useLightbox } from '@/components/ui/lightbox'
import { isVideoUrl, urlToMedia } from '@/lib/media'

// Per-scene state → a solid icon dot on the thumb (label rides the tooltip),
// so the strip stays tiny and the player keeps the room. `working` states get a
// pulsing overlay so a queued scene never reads as idle.
const STATE_META = {
  ready:     { get label() { return i18n.t('ticket:video.state.ready') },     dot: 'bg-emerald text-white', icon: Check },
  rendering: { get label() { return i18n.t('ticket:video.state.rendering') }, dot: 'bg-sky text-white',     icon: Loader2, spin: true, working: true },
  stale:     { get label() { return i18n.t('ticket:video.state.queued') },    dot: 'bg-amber text-white',   icon: Loader2, spin: true, working: true },
  fresh:     { get label() { return i18n.t('ticket:video.state.queued') },    dot: 'bg-amber text-white',   icon: Loader2, spin: true, working: true },
  failed:    { get label() { return i18n.t('ticket:video.state.failed') },    dot: 'bg-danger text-white',  icon: AlertCircle },
}

// The player box follows the video's real aspect — a 16:9 video in a fixed
// 9:16 box was a sliver with giant letterboxes.
const ASPECT_CLS = {
  '9:16': 'aspect-[9/16]', '1:1': 'aspect-square', '4:5': 'aspect-[4/5]', '16:9': 'aspect-video',
}

const WORKING_STATES = ['rendering', 'fresh', 'stale']
const isBusy = (scenes) => scenes.some((s) => WORKING_STATES.includes(s.render_state))
const workingScenes = (scenes) => scenes.filter((s) => WORKING_STATES.includes(s.render_state))

// "cena 2", "cenas 1 e 3", "cenas 1, 2 e 4" — for the progress banner copy.
const sceneList = (nums) => {
  const n = [...new Set(nums)].sort((a, b) => a - b)
  if (n.length === 0) return ''
  if (n.length === 1) return i18n.t('ticket:video.sceneOne', { num: n[0] })
  return i18n.t('ticket:video.sceneMany', { head: n.slice(0, -1).join(', '), last: n[n.length - 1] })
}

const fmtTime = (secs) => {
  const s = Math.max(0, Math.round(secs))
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}

// ── SequencePlayer: plays the scene clips as ONE continuous video ──────
// A single <video> that hops to the next clip on end, under a global timecode
// bar segmented per scene. Clicking a segment (or a timeline thumb) seeks there.
// Two modes, one experience:
//   * composed — the final single file exists: ONE <video> plays it end to end
//     (true continuous audio/motion); the bar maps scenes onto its timeline.
//   * clip-hop — while scenes are still rendering: hops clips seamlessly on end
//     (next clip preloaded), under the same global timecode.
function SequencePlayer({ scenes, composedUrl, music, jumpTo, onJumped, onProgress, onFullscreen }) {
  const { t } = useTranslation('ticket')
  const playable = useMemo(() => scenes.filter((s) => s.clip_url), [scenes])
  const single = !!composedUrl
  const segments = single ? scenes : playable
  const videoRef = useRef(null)
  const musicRef = useRef(null)
  const [idx, setIdx] = useState(0)          // clip-hop: which clip is mounted
  const [playing, setPlaying] = useState(false)
  // The composed file has the music burned in; in clip-hop preview the clips are
  // music-free, so we play the chosen track under them (an approximation of the
  // final mix) whenever the preview is playing.
  const previewMusic = !single && music?.url ? music.url : null
  useEffect(() => {
    const a = musicRef.current
    if (!a) return
    if (playing) { a.volume = 0.35; a.play().catch(() => {}) } else { a.pause() }
  }, [playing, previewMusic])
  const [localTime, setLocalTime] = useState(0)
  // Real duration of the composed file (single mode) — the DB scene durations
  // are estimates and can drift from the actual media; the file is the truth.
  const [mediaDuration, setMediaDuration] = useState(null)

  const sceneDurations = segments.map((s) => Number(s.duration_seconds) || 0)
  const sceneSum = sceneDurations.reduce((a, b) => a + b, 0) || segments.length
  // In single mode, everything maps onto the REAL file duration: each scene's
  // slice is its proportional share, so the timecode and playhead stay honest.
  const total = single ? (mediaDuration || sceneSum) : sceneSum
  const durations = sceneDurations.map((d) => (d / sceneSum) * total)
  const offsets = useMemo(() => {
    const acc = []
    durations.reduce((sum, d, i) => { acc[i] = sum; return sum + d }, 0)
    return acc
  }, [JSON.stringify(durations)]) // eslint-disable-line react-hooks/exhaustive-deps

  const current = playable[Math.min(idx, playable.length - 1)]
  const globalTime = single ? localTime : (offsets[idx] || 0) + localTime
  // Which scene the playhead is inside (drives the "Cena X/Y" readout).
  const activeIdx = single
    ? Math.max(0, offsets.findLastIndex((off) => globalTime >= off))
    : Math.min(idx, playable.length - 1)

  // Feed the scene strip (the visual timeline) with the playhead position.
  useEffect(() => {
    onProgress?.({ activeIdx, globalTime, offsets, durations, playing })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeIdx, Math.round(globalTime * 4), playing])

  const seekTo = (globalSecs) => {
    if (single) {
      if (videoRef.current) videoRef.current.currentTime = Math.max(0, globalSecs)
      return
    }
    let target = 0
    while (target < playable.length - 1 && globalSecs >= (offsets[target] || 0) + durations[target]) target += 1
    const within = Math.max(0, globalSecs - (offsets[target] || 0))
    if (target !== idx) {
      setIdx(target)
      setLocalTime(within)
      // Seek after the new clip mounts; autoplay keeps the flow if it was playing.
      requestAnimationFrame(() => { if (videoRef.current) videoRef.current.currentTime = within })
    } else if (videoRef.current) {
      videoRef.current.currentTime = within
    }
  }

  // External jump (timeline thumb click) → seek to that scene's start.
  useEffect(() => {
    if (jumpTo == null) return
    const target = segments.findIndex((s) => s.id === jumpTo)
    if (target >= 0) seekTo(offsets[target] || 0)
    onJumped?.()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [jumpTo])

  // Reset when the scene set changes shape (re-render finished etc.).
  useEffect(() => { if (!single && idx >= playable.length) { setIdx(0); setLocalTime(0) } }, [single, playable.length, idx])

  const play = () => { videoRef.current?.play() }
  const pause = () => { videoRef.current?.pause() }

  const onBarClick = (e) => {
    const rect = e.currentTarget.getBoundingClientRect()
    const frac = (e.clientX - rect.left) / rect.width
    seekTo(frac * total)
  }

  const src = single ? composedUrl : current?.clip_url
  if (!src) return null

  return (
    <div className="flex size-full flex-col gap-2">
      <div className="relative min-h-0 flex-1">
        <video
          key={single ? 'composed' : current.id}
          ref={videoRef}
          src={src}
          poster={single ? undefined : (current.thumbnail_url || undefined)}
          playsInline
          autoPlay={playing}
          onPlay={() => setPlaying(true)}
          onPause={() => setPlaying(false)}
          onLoadedMetadata={(e) => {
            if (single) setMediaDuration(e.currentTarget.duration || null)
            // Uninterrupted hop: guarantee the next clip starts even if the
            // autoPlay attribute is ignored on remount.
            if (playing) e.currentTarget.play().catch(() => {})
          }}
          onTimeUpdate={(e) => setLocalTime(e.currentTarget.currentTime)}
          onEnded={() => {
            if (!single && idx + 1 < playable.length) { setIdx(idx + 1); setLocalTime(0) } else { setPlaying(false) }
          }}
          onClick={() => (playing ? pause() : play())}
          className="size-full cursor-pointer rounded-2xl bg-black object-contain"
        />
        {/* Preview soundtrack (clip-hop only — the composed file has it burned in). */}
        {previewMusic && <audio ref={musicRef} src={previewMusic} loop preload="auto" className="hidden" />}
        {/* Preload the next clip so the hop is seamless — one video, no gap. */}
        {!single && playable[idx + 1] && (
          <video src={playable[idx + 1].clip_url} preload="auto" muted className="hidden" />
        )}
        {!playing && (
          <button
            type="button" onClick={play} aria-label={t('video.play')}
            className="absolute inset-0 grid place-items-center rounded-2xl bg-black/20 text-white transition hover:bg-black/30"
          >
            <span className="grid size-14 place-items-center rounded-full bg-white/25 backdrop-blur"><Play size={26} /></span>
          </button>
        )}
      </div>

      {/* Global timecode bar, segmented per scene */}
      <div className="shrink-0">
        <div className="flex h-2 w-full cursor-pointer gap-0.5" onClick={onBarClick} role="presentation">
          {segments.map((s, i) => {
            const frac = total > 0 ? (durations[i] / total) : 1 / segments.length
            const within = durations[i] ? Math.min(1, Math.max(0, (globalTime - (offsets[i] || 0)) / durations[i])) : 0
            const sceneProgress = i < activeIdx ? 1 : i > activeIdx ? 0 : within
            return (
              <div key={s.id} className="relative overflow-hidden rounded-full bg-surface-muted" style={{ width: `${frac * 100}%` }}>
                <div className="absolute inset-y-0 left-0 bg-brand" style={{ width: `${sceneProgress * 100}%` }} />
              </div>
            )
          })}
        </div>
        <div className="mt-1 flex items-center justify-between text-[11px] font-semibold tabular-nums text-ink-muted">
          <button type="button" onClick={() => (playing ? pause() : play())} className="inline-flex items-center gap-1 text-ink-secondary hover:text-ink">
            {playing ? <Pause size={12} /> : <Play size={12} />} {fmtTime(globalTime)} / {fmtTime(total)}
          </button>
          <span className="flex items-center gap-3">
            {single && onFullscreen && (
              <button
                type="button"
                onClick={onFullscreen}
                title={t('video.fullscreenTitle')}
                className="inline-flex items-center gap-1 font-bold text-ink-secondary transition hover:text-ink"
              >
                <Maximize2 size={12} /> {t('video.fullscreen')}
              </button>
            )}
            {single && (
              <a
                href={`${composedUrl}${composedUrl.includes('?') ? '&' : '?'}disposition=attachment`}
                download
                title={t('video.downloadTitle')}
                className="inline-flex items-center gap-1 font-bold text-ink-secondary transition hover:text-ink"
              >
                <Download size={12} /> {t('actions.download')}
              </a>
            )}
            <span>{t('video.sceneCounter', { current: activeIdx + 1, total: segments.length })}</span>
          </span>
        </div>
      </div>
    </div>
  )
}

// ── Placeholder when there's nothing playable yet ─────────────────────
function PreviewPlaceholder({ busy, failed, planning }) {
  const { t } = useTranslation('ticket')
  return (
    <div className="grid size-full place-items-center rounded-2xl bg-brand-ink/90 text-white/70">
      {failed ? (
        <div className="flex flex-col items-center gap-2 px-4 text-center text-white/85">
          <AlertCircle size={26} className="text-danger" />
          <p className="text-sm font-semibold">{t('video.generationFailed')}</p>
          <p className="text-xs text-white/60">{t('video.generationFailedHint')}</p>
        </div>
      ) : busy ? (
        <div className="flex flex-col items-center gap-2 text-center">
          <InlineSpinner size={26} />
          <p className="text-xs">{planning ? t('video.planning') : t('video.rendering')}</p>
        </div>
      ) : <Film size={28} />}
    </div>
  )
}

// ── Timeline: the scenes as a scrubbable strip WITH a playhead ─────────
// Each thumb doubles as a timeline segment: a story-style progress fill sweeps
// across it while the player is inside that scene (fed by SequencePlayer).
function Timeline({ scenes, onSeek, playhead, noteFor, onSaveNote }) {
  return (
    <div className="flex gap-1.5 overflow-x-auto pb-1">
      {scenes.map((s, i) => {
        const isPlayhead = playhead && playhead.activeIdx === i
        const within = isPlayhead && playhead.durations?.[i]
          ? Math.min(1, Math.max(0, (playhead.globalTime - (playhead.offsets?.[i] || 0)) / playhead.durations[i]))
          : (playhead && i < playhead.activeIdx ? 1 : 0)
        return (
          <SceneTile
            key={s.id}
            scene={s}
            isPlayhead={isPlayhead}
            within={within}
            note={noteFor(s.position + 1)}
            onSeek={() => onSeek(s)}
            onSaveNote={(text, refs) => onSaveNote(s.position + 1, text, refs)}
          />
        )
      })}
    </div>
  )
}

// One scene in the strip: a thumbnail that doubles as a timeline segment AND the
// anchor for its ANNOTATION balloon. Click → a popover to note the scene (edit
// the same note by clicking again); the saved note shows as a chip above the
// chat input and rides along with the next message.
function SceneTile({ scene: s, isPlayhead, within, note, onSeek, onSaveNote }) {
  const { t } = useTranslation('ticket')
  const m = STATE_META[s.render_state] || STATE_META.fresh
  const StateIcon = m.icon
  const [open, setOpen] = useState(false)
  const [draft, setDraft] = useState('')
  const [draftRefs, setDraftRefs] = useState([]) // [{ url, kind }] pinned to THIS scene
  const [uploading, setUploading] = useState(false)
  const fileRef = useRef(null)
  const pinned = (note.text || '') || (note.refs?.length > 0)

  const openBalloon = () => { setDraft(note.text || ''); setDraftRefs(note.refs || []); setOpen(true); onSeek() }
  const save = () => { onSaveNote(draft.trim(), draftRefs); setOpen(false) }
  const clear = () => { onSaveNote('', []); setOpen(false) }

  // A reference attached here rides with this scene's annotation → straight to
  // the scene's render process on send (item 3). Image or short guide video.
  const pickRef = async (e) => {
    const files = Array.from(e.target.files || [])
    e.target.value = ''
    if (!files.length || draftRefs.length >= 2) return
    setUploading(true)
    try {
      const { references: uploaded } = await uploadsApi.references(files.slice(0, 2 - draftRefs.length))
      setDraftRefs((prev) => [...prev, ...uploaded].slice(0, 2))
    } catch {
      toast.error(t('video.attachError'))
    } finally {
      setUploading(false)
    }
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          type="button"
          title={t('video.sceneTileTitle', { num: s.position + 1 })}
          onClick={openBalloon}
          className={cn(
            'relative h-20 w-12 shrink-0 overflow-hidden rounded-lg border-2 text-left transition',
            open ? 'border-brand ring-2 ring-brand/20'
              : s.render_state === 'failed' ? 'border-danger/70'
              : pinned ? 'border-brand/50'
              : isPlayhead ? 'border-brand/60' : 'border-border hover:border-brand/40',
          )}
        >
          <div className="relative size-full bg-brand-ink/90">
            {s.clip_url ? (
              <video src={`${s.clip_url}#t=0.1`} muted playsInline preload="metadata" className="size-full object-cover" />
            ) : (
              <div className="grid size-full place-items-center text-white/60"><Film size={14} /></div>
            )}
            {m.working && (
              <div className="absolute inset-0 grid animate-pulse place-items-center bg-brand-ink/45 text-white">
                <InlineSpinner size={16} />
              </div>
            )}
            <span className="absolute left-0.5 top-0.5 grid size-4 place-items-center rounded bg-black/60 text-[9px] font-bold text-white">
              {s.position + 1}
            </span>
            {/* A note badge, or the render-state dot when there's no note. */}
            {pinned ? (
              <span className="absolute right-0.5 top-0.5 grid size-4 place-items-center rounded-full bg-brand text-white shadow-sm">
                {note.refs?.length ? <ImagePlus size={9} /> : <Pencil size={9} />}
              </span>
            ) : (
              <span className={cn('absolute right-0.5 top-0.5 grid size-4 place-items-center rounded-full shadow-sm', m.dot)}>
                <StateIcon size={9} className={m.spin ? 'animate-spin' : ''} />
              </span>
            )}
            <span className="absolute inset-x-0 bottom-0 h-1 bg-black/30">
              <span className="absolute inset-y-0 left-0 bg-brand transition-[width] duration-200" style={{ width: `${within * 100}%` }} />
            </span>
          </div>
        </button>
      </PopoverTrigger>
      <PopoverContent align="center" side="top" className="w-64">
        <SectionLabel className="mb-1.5 tracking-wider text-ink-secondary">
          {t('video.annotateScene', { num: s.position + 1 })}
        </SectionLabel>
        <Textarea
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            // Single-line comment: Enter submits (Shift+Enter for a rare newline).
            if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); save() }
          }}
          placeholder={t('video.annotatePlaceholder')}
          rows={2}
          autoFocus
          className="min-h-12 text-sm"
        />
        {/* A reference pinned to THIS scene — goes straight to its render (item 3). */}
        <input
          ref={fileRef} type="file" multiple hidden onChange={pickRef}
          accept="image/jpeg,image/png,image/webp,video/mp4,video/quicktime,video/webm"
        />
        <div className="mt-2 space-y-1.5">
          {draftRefs.map((r, i) => (
            <div key={r.url} className="flex items-center gap-1.5">
              <div className="relative size-9 shrink-0 overflow-hidden rounded-lg border border-border">
                {r.kind === 'vid'
                  ? <video src={r.url} muted preload="metadata" className="size-full object-cover" />
                  : <img src={r.url} alt={t('video.referenceAlt')} className="size-full object-cover" />}
              </div>
              <input
                value={r.description || ''}
                onChange={(e) => setDraftRefs((prev) => prev.map((x, j) => (j === i ? { ...x, description: e.target.value } : x)))}
                placeholder={t('video.whatIsThisFile')}
                className="h-8 min-w-0 flex-1 rounded-lg border border-border bg-surface px-2 text-xs text-ink placeholder:text-ink-faint focus:border-brand focus:outline-none"
              />
              <button
                type="button" onClick={() => setDraftRefs((prev) => prev.filter((_, j) => j !== i))}
                aria-label={t('actions.remove')} className="grid size-5 shrink-0 place-items-center rounded text-ink-muted transition hover:text-danger"
              >
                <X size={11} />
              </button>
            </div>
          ))}
          {draftRefs.length < 2 && (
            <button
              type="button" onClick={() => fileRef.current?.click()} disabled={uploading}
              title={t('video.attachReferenceScene')}
              className="flex h-9 w-full items-center justify-center gap-1.5 rounded-lg border border-dashed border-border-strong text-xs font-semibold text-ink-muted transition hover:border-brand hover:text-brand disabled:opacity-50"
            >
              {uploading ? <InlineSpinner size={14} /> : <><ImagePlus size={14} /> {t('video.attachReference')}</>}
            </button>
          )}
        </div>
        <div className="mt-2 flex justify-end gap-2">
          {pinned && (
            <Button size="sm" variant="ghost" className="h-8" onClick={clear}>
              {t('actions.remove')}
            </Button>
          )}
          <Button size="sm" className="h-8" onClick={save} disabled={!draft.trim() && draftRefs.length === 0}>
            <Check size={14} /> {t('actions.save')}
          </Button>
        </div>
      </PopoverContent>
    </Popover>
  )
}

// A render problem, explained kindly in the chat — so a copyright/audio/safety
// block from the video model reads as guidance, not a dead red tile.
function AlertMessage({ content }) {
  return (
    <div className="flex justify-start">
      <div className="flex max-w-[92%] items-start gap-2.5 rounded-2xl border border-amber/30 bg-amber/10 px-3.5 py-2.5 text-sm text-ink">
        <TriangleAlert size={16} className="mt-0.5 shrink-0 text-[#B45309]" />
        <Markdown className="min-w-0 prose-p:first:mt-0 prose-p:last:mb-0">{content.replace(/^⚠️\s*/, '')}</Markdown>
      </div>
    </div>
  )
}

// Reference thumbnails kept in a chat message — a square black tile (so any
// aspect fits without cropping, object-contain) that FLOATS slightly over the
// bubble's bottom edge to tie it to the message. Clicking opens the in-app
// lightbox (NOT a new tab — a top-level nav would hit the ngrok warning page).
function MessageThumbs({ images, align = 'start', onOpen }) {
  const { t } = useTranslation('ticket')
  return (
    <div className={cn('-mt-3 flex flex-wrap gap-1.5 px-1', align === 'end' ? 'justify-end' : 'justify-start')}>
      {images.map((url) => (
        <button
          key={url} type="button" onClick={() => onOpen?.(url)} title={t('video.openReference')}
          className="size-14 shrink-0 overflow-hidden rounded-lg bg-black shadow-md ring-1 ring-border transition hover:ring-2 hover:ring-brand"
        >
          {isVideoUrl(url)
            ? <video src={url} muted preload="metadata" className="size-full object-contain" />
            : <img src={url} alt={t('video.referenceAlt')} className="size-full object-contain" />}
        </button>
      ))}
    </div>
  )
}

// The per-bubble cost tag: sits right under the assistant bubble whose turn
// spent credits, so the price is tied to the exact operation that caused it.
function CreditTag({ credits }) {
  const { t } = useTranslation('ticket')
  return (
    <div className="flex animate-rise justify-start pl-1">
      <Badge variant="warning" className="px-2 text-[11px] tracking-normal">
        <Coins size={11} /> {t('video.creditsSpent', { count: credits })}
      </Badge>
    </div>
  )
}

// ── Chat: talk to the whole video; scene notes + attached reference images
// buffer up and ride along with the next message ───────────────────────
const MAX_CHAT_REFS = 3

function Chat({ messages, notes, onRemoveNote, onSend, sending, working = [], creditBalance = null }) {
  const { t } = useTranslation('ticket')
  const lightbox = useLightbox()
  const [text, setText] = useState('')
  const [refs, setRefs] = useState([]) // [{ url }] attached reference images
  const [uploading, setUploading] = useState(false)
  const scrollRef = useRef(null)
  const fileRef = useRef(null)

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' })
  }, [messages, sending, working.length])

  const pickRefs = async (e) => {
    const files = Array.from(e.target.files || [])
    e.target.value = ''
    if (!files.length) return
    const room = MAX_CHAT_REFS - refs.length
    if (room <= 0) { toast.error(t('video.maxRefs', { count: MAX_CHAT_REFS })); return }
    setUploading(true)
    try {
      const { references: uploaded } = await uploadsApi.references(files.slice(0, room))
      setRefs((prev) => [...prev, ...uploaded].slice(0, MAX_CHAT_REFS))
    } catch {
      toast.error(t('video.uploadError'))
    } finally {
      setUploading(false)
    }
  }

  const hasNotes = notes.length > 0

  const submit = () => {
    const msg = text.trim()
    if ((!msg && refs.length === 0 && !hasNotes) || sending) return
    // Scene annotations (set via the tile balloons) + attachments ride along
    // with the message. With only notes and no typed text, still send so the
    // annotations get applied. Each ref carries the user's description.
    onSend(msg || (hasNotes ? t('video.applyNotes') : t('video.useReference')), refs)
    setText('')
    setRefs([])
  }

  const setRefDescription = (i, description) =>
    setRefs((prev) => prev.map((r, j) => (j === i ? { ...r, description } : r)))

  return (
    <div className="flex min-h-0 flex-1 flex-col rounded-2xl border border-border bg-surface-muted/30">
      <div ref={scrollRef} className="scrollbar-subtle min-h-0 flex-1 space-y-3 overflow-y-auto p-3">
        {messages.length === 0 ? (
          <div className="flex h-full flex-col items-center justify-center gap-2 px-4 text-center text-ink-muted">
            <MessageSquare size={22} className="text-brand" />
            <p className="text-sm font-semibold text-ink">{t('video.chatTitle')}</p>
            <p className="text-xs">{t('video.chatHint')}</p>
          </div>
        ) : (
          messages.map((m, i) => (
            m.kind === 'alert'
              ? <AlertMessage key={i} content={m.content} />
              : (
                <div key={i} className="space-y-1">
                  {m.content?.trim() && <Bubble role={m.role} content={m.content} />}
                  {/* Attached references kept in the transcript — clickable thumbnails.
                      Opening one opens the whole message's references as a deck. */}
                  {m.images?.length > 0 && (
                    <MessageThumbs
                      images={m.images}
                      align={m.role === 'user' ? 'end' : 'start'}
                      onOpen={(url) => lightbox.open(
                        m.images.map((u) => urlToMedia(u, { name: t('video.elementCap') })),
                        Math.max(0, m.images.indexOf(url)),
                      )}
                    />
                  )}
                  {/* The cost sits UNDER the exact bubble whose turn spent credits. */}
                  {m.credits > 0 && <CreditTag credits={m.credits} />}
                </div>
              )
          ))
        )}
        {/* Continuous feedback, right where the user is looking: the agent is
            thinking (dots) → then the render is running (named, animated). No
            dead moment between the reply and the scenes updating. */}
        {sending ? (
          <TypingDots />
        ) : working.length > 0 && (
          <div className="flex justify-start">
            <div className="inline-flex items-center gap-2 rounded-2xl bg-brand-soft/50 px-3.5 py-2 text-xs font-semibold text-brand">
              <InlineSpinner size={13} className="shrink-0" />
              {t('video.workingChat', { count: working.length, scenes: sceneList(working) })}
            </div>
          </div>
        )}
      </div>

      <div className="border-t border-border p-2.5">
        {/* Scene annotations (set on the tiles) — sent with the next message.
            Removable here; editable by clicking the scene again. */}
        {hasNotes && (
          <div className="mb-1.5 flex flex-wrap items-center gap-1.5">
            {notes.map((n) => (
              <Badge key={n.scene} className="max-w-full bg-brand-soft/60 px-2 text-[11px] font-semibold tracking-normal text-brand">
                {n.refs?.length ? <ImagePlus size={10} className="shrink-0" /> : <Pencil size={10} className="shrink-0" />}
                <span className="truncate">
                  {n.refs?.length
                    ? t('video.sceneNoteWithRefs', { num: n.scene, text: n.text || t('video.referenceAttached'), count: n.refs.length })
                    : t('video.sceneNote', { num: n.scene, text: n.text || t('video.referenceAttached') })}
                </span>
                <button type="button" onClick={() => onRemoveNote(n.scene)} aria-label={t('video.removeNoteAria')} className="shrink-0 opacity-70 hover:opacity-100">
                  <X size={11} />
                </button>
              </Badge>
            ))}
          </div>
        )}
        {/* Attached media references (image or video) — each asks "what is this?"
            so the editor knows how to use the file; rides with the next message. */}
        {refs.length > 0 && (
          <div className="mb-1.5 space-y-1.5">
            {refs.map((r, i) => (
              <div key={r.url} className="flex items-center gap-2">
                <div className="relative size-10 shrink-0 overflow-hidden rounded-lg border border-border">
                  {r.kind === 'vid'
                    ? <video src={r.url} muted preload="metadata" className="size-full object-cover" />
                    : <img src={r.url} alt={t('video.referenceAlt')} className="size-full object-cover" />}
                </div>
                <input
                  value={r.description || ''}
                  onChange={(e) => setRefDescription(i, e.target.value)}
                  placeholder={t('video.whatIsFileExample')}
                  className="h-9 min-w-0 flex-1 rounded-lg border border-border bg-surface px-2.5 text-xs text-ink placeholder:text-ink-faint focus:border-brand focus:outline-none"
                />
                <button
                  type="button" onClick={() => setRefs((prev) => prev.filter((_, j) => j !== i))}
                  aria-label={t('actions.remove')} className="grid size-6 shrink-0 place-items-center rounded-md text-ink-muted transition hover:text-danger"
                >
                  <X size={13} />
                </button>
              </div>
            ))}
          </div>
        )}
        <input
          ref={fileRef} type="file" multiple hidden onChange={pickRefs}
          accept="image/jpeg,image/png,image/webp,video/mp4,video/quicktime,video/webm"
        />
        <div className="flex items-stretch gap-1.5">
          <button
            type="button" onClick={() => fileRef.current?.click()}
            disabled={sending || uploading || refs.length >= MAX_CHAT_REFS}
            title={t('video.attachRefTitle')}
            className="grid h-[52px] w-11 shrink-0 place-items-center rounded-xl border border-border text-ink-muted transition hover:border-brand hover:text-brand disabled:opacity-40"
          >
            {uploading ? <InlineSpinner size={16} /> : <ImagePlus size={16} />}
          </button>
          <div className="min-w-0 flex-1">
            <ChatComposer
              value={text}
              onChange={setText}
              onSend={submit}
              sending={sending}
              placeholder={
                refs.length ? t('video.composerRef')
                  : hasNotes ? t('video.composerNotes')
                    : t('video.composerDefault')
              }
            />
          </div>
        </div>
        {/* Wallet balance — right under the send button, so the cost of the next
            edit is always in view (moved here from the dialog title). */}
        <div className="mt-1.5 flex justify-end">
          <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-ink-muted">
            <Coins size={12} className="text-[#B45309]" />
            {t('video.creditsBalance', { value: creditBalance === null ? '∞' : `${creditBalance ?? '—'}` })}
          </span>
        </div>
      </div>
    </div>
  )
}

// A prominent, always-legible progress banner in the main column — the clear
// "something is happening" signal that closes the gap between the agent's reply
// and the tiny scene chips. Three moments:
//   * sending — the turn is in flight (agent thinking + queuing the render)
//   * working — scenes are rendering/queued (names them; ~1–2 min per scene)
//   * finalizing — the high-quality pass is running over the approved draft
function WorkBanner({ sending, workingNums, finalizing }) {
  const { t } = useTranslation('ticket')
  if (!sending && workingNums.length === 0) return null

  let text
  if (sending && workingNums.length === 0) {
    text = t('video.applying')
  } else if (finalizing) {
    text = t('video.finalizing', { scenes: sceneList(workingNums) })
  } else {
    text = t('video.workingBanner', { count: workingNums.length, scenes: sceneList(workingNums) })
  }

  return (
    <div className="shrink-0 overflow-hidden rounded-xl border border-brand/30 bg-brand-soft/40">
      <div className="flex items-center gap-2 px-3 py-2 text-xs font-semibold text-ink">
        <InlineSpinner size={14} className="shrink-0 text-brand" />
        {text}
      </div>
      {/* Indeterminate sweep — motion the eye catches even from the chat side. */}
      <div className="h-0.5 w-full overflow-hidden bg-brand/15">
        <div className="anim-indeterminate h-full w-1/3 rounded-full bg-brand" />
      </div>
    </div>
  )
}

// The right pane during the INTERVIEW: no video yet — a calm placeholder that
// tells the user the chat is gathering context and will build when ready.
function InterviewPane({ sending }) {
  const { t } = useTranslation('ticket')
  return (
    <div className="max-w-xs text-center text-ink-muted">
      <div className="mx-auto grid size-14 place-items-center rounded-2xl bg-brand-soft/50 text-brand">
        {sending ? <InlineSpinner size={26} /> : <MessageSquare size={26} />}
      </div>
      <p className="mt-3 text-sm font-semibold text-ink">{t('video.interviewTitle')}</p>
      <p className="mt-1 text-xs">
        {t('video.interviewHint')}
      </p>
    </div>
  )
}

// ── Elementos tab ─────────────────────────────────────────────────────
// Every element the video uses: recurring CHARACTERS, SCENARIOS, other typed
// REFERENCES (product/logo/style/…) fed to the render, and the background MUSIC.
// You can ADD (upload or from the library), REGENERATE (character/scenario, 1
// image credit) and REMOVE elements. Changes never re-render the current scenes —
// the element is used on the NEXT render. Music is a free re-search + re-mix.

// The tab switcher between the conversational editor and the assets list.
function TabBar({ tab, onChange }) {
  const { t } = useTranslation('ticket')
  const tabs = [
    { key: 'edicao', label: t('video.tabEdit'), icon: Clapperboard },
    { key: 'assets', label: t('video.tabAssets'), icon: Boxes },
  ]
  return (
    <div className="flex shrink-0 gap-1 rounded-xl border border-border bg-surface-muted/40 p-1">
      {tabs.map(({ key, label, icon: Icon }) => (
        <button
          key={key}
          type="button"
          onClick={() => onChange(key)}
          className={cn(
            'inline-flex flex-1 items-center justify-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-bold transition',
            tab === key ? 'bg-surface text-ink shadow-sm' : 'text-ink-muted hover:text-ink',
          )}
        >
          <Icon size={14} /> {label}
        </button>
      ))}
    </div>
  )
}

// One element card: its reference image (or a placeholder), a role chip + the
// description, and its actions — an inline "regenerate from a prompt" editor
// (characters/scenarios only, via `regenType`) and "remove". Changes never
// re-render the current scenes; the element is used on the next render.
function AssetCard({ item, regenType, regen, onRemove, onOpen }) {
  const { t } = useTranslation('ticket')
  const [editing, setEditing] = useState(false)
  const [prompt, setPrompt] = useState(item.description || '')
  const canRegen = !!regenType
  const busy = regen.isPending && regen.variables?.type === regenType &&
    (regen.variables?.ref_url || null) === (item.image_url || null)

  const submit = () => {
    const text = prompt.trim()
    if (!text || busy) return
    regen.mutate(
      { type: regenType, prompt: text, ref_url: item.image_url || undefined },
      { onSuccess: () => setEditing(false) },
    )
  }

  const placeholder = item.role === 'character' || item.role === 'avatar' ? <UserRound size={22} /> : <ImageIcon size={22} />
  const thumbClass = 'grid size-20 shrink-0 place-items-center overflow-hidden rounded-xl bg-brand-ink/90 text-white/50'

  return (
    <div className="rounded-2xl border border-border bg-surface-muted/30 p-3">
      <div className="flex gap-3">
        {item.image_url ? (
          <button
            type="button" onClick={() => onOpen?.(item)} title={t('video.viewFullscreen')}
            className={cn(thumbClass, 'cursor-zoom-in transition hover:ring-2 hover:ring-brand')}
          >
            {item.kind === 'vid'
              ? <video src={item.image_url} muted playsInline preload="metadata" className="size-full object-cover" />
              : <img src={item.image_url} alt="" className="size-full object-cover" />}
          </button>
        ) : (
          <div className={thumbClass}>{placeholder}</div>
        )}
        <div className="flex min-w-0 flex-1 flex-col">
          <Badge className="mb-1 w-fit bg-brand-soft/60 px-2 text-[10px] uppercase text-brand">
            {item.role_label}
          </Badge>
          <p className="line-clamp-2 text-xs leading-relaxed text-ink-secondary">
            {item.description || (canRegen ? t('video.noDescription') : t('video.videoReference'))}
          </p>
          <div className="mt-auto flex items-center gap-1 pt-2">
            {canRegen && (
              <Button size="sm" variant="ghost" className="h-7 px-2" onClick={() => setEditing((v) => !v)}>
                <Wand2 size={13} /> {item.image_url ? t('video.regenerate') : t('video.generateImage')}
              </Button>
            )}
            <Button size="sm" variant="ghost" className="h-7 px-2 text-ink-muted hover:text-danger" onClick={() => onRemove(item)}>
              <Trash2 size={13} /> {t('actions.remove')}
            </Button>
          </div>
        </div>
      </div>
      {editing && canRegen && (
        <div className="mt-2.5 border-t border-border pt-2.5">
          <Textarea
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
            placeholder={regenType === 'character' ? t('video.characterPlaceholder') : t('video.scenarioPlaceholder')}
            rows={2}
            autoFocus
            className="min-h-14 text-sm"
          />
          <div className="mt-2 flex items-center justify-between gap-2">
            <span className="text-[11px] font-medium text-ink-muted">{t('video.regenCost')}</span>
            <Button size="sm" className="h-8" onClick={submit} disabled={busy || !prompt.trim()}>
              {busy ? <InlineSpinner size={14} /> : <Sparkles size={14} />} {t('video.generate')}
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}

// A titled group of element cards (hidden entirely when it has no items).
function AssetSection({ title, icon: Icon, items, regenType, regen, onRemove, onOpen }) {
  if (!items?.length) return null
  return (
    <div>
      <SectionLabel className="mb-2 flex items-center gap-1.5 tracking-wider text-ink-secondary">
        <Icon size={13} className="text-brand" /> {title}
      </SectionLabel>
      <div className="grid gap-2 sm:grid-cols-2">
        {items.map((item) => (
          <AssetCard key={item.key} item={item} regenType={regenType} regen={regen} onRemove={onRemove} onOpen={onOpen} />
        ))}
      </div>
    </div>
  )
}

// The soundtrack asset: a playable preview + a prompt to re-search the track.
function MusicCard({ music, regen }) {
  const { t } = useTranslation('ticket')
  const [editing, setEditing] = useState(false)
  const [prompt, setPrompt] = useState(music.mood || '')
  const busy = regen.isPending && regen.variables?.type === 'music'

  const submit = () => {
    const text = prompt.trim()
    if (!text || busy) return
    regen.mutate({ type: 'music', prompt: text }, { onSuccess: () => setEditing(false) })
  }

  return (
    <div>
      <SectionLabel className="mb-2 flex items-center gap-1.5 tracking-wider text-ink-secondary">
        <Music size={13} className="text-brand" /> {t('video.soundtrack')}
      </SectionLabel>
      <div className="rounded-2xl border border-border bg-surface-muted/30 p-3">
        <div className="flex items-center justify-between gap-2">
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-ink">{music.title || music.attribution || t('video.currentTrack')}</p>
            {music.attribution && music.title && <p className="truncate text-xs text-ink-muted">{music.attribution}</p>}
          </div>
          <Button size="sm" variant="ghost" className="h-7 shrink-0 px-2" onClick={() => setEditing((v) => !v)}>
            <Wand2 size={13} /> {t('video.swap')}
          </Button>
        </div>
        {music.url && <audio src={music.url} controls preload="none" className="mt-2 h-8 w-full" />}
        {editing && (
          <div className="mt-2.5 border-t border-border pt-2.5">
            <Textarea
              value={prompt}
              onChange={(e) => setPrompt(e.target.value)}
              placeholder={t('video.musicPlaceholder')}
              rows={2}
              autoFocus
              className="min-h-14 text-sm"
            />
            <div className="mt-2 flex items-center justify-between gap-2">
              <span className="text-[11px] font-medium text-ink-muted">{t('video.musicFree')}</span>
              <Button size="sm" className="h-8" onClick={submit} disabled={busy || !prompt.trim()}>
                {busy ? <InlineSpinner size={14} /> : <Sparkles size={14} />} {t('video.swapTrack')}
              </Button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

// Roles offered when adding an uploaded element (localized labels).
const ADD_ROLES = [
  { value: 'character', get label() { return i18n.t('ticket:video.roles.character') } },
  { value: 'scene', get label() { return i18n.t('ticket:video.roles.scene') } },
  { value: 'product', get label() { return i18n.t('ticket:video.roles.product') } },
  { value: 'style', get label() { return i18n.t('ticket:video.roles.style') } },
  { value: 'logo', get label() { return i18n.t('ticket:video.roles.logo') } },
  { value: 'reference', get label() { return i18n.t('ticket:video.roles.reference') } },
]

// Add an element: upload a file (typed under a role) or pick one from the library
// (brand avatar/logo + characters/scenarios used in other videos). Both add the
// element to every scene for the NEXT render — no re-render, no credits.
function AddElement({ creativeId }) {
  const { t } = useTranslation('ticket')
  const [open, setOpen] = useState(false)
  const [mode, setMode] = useState('upload')
  const [role, setRole] = useState('character')
  const [uploading, setUploading] = useState(false)
  const add = useAddAsset(creativeId)
  const { data: lib, isLoading: libLoading } = useAssetLibrary(creativeId, { enabled: open && mode === 'library' })
  const fileRef = useRef(null)
  const items = lib?.items || []

  const pickFile = async (e) => {
    const files = Array.from(e.target.files || [])
    e.target.value = ''
    if (!files.length) return
    setUploading(true)
    try {
      const { references } = await uploadsApi.references(files.slice(0, 1))
      const ref = references[0]
      if (ref) add.mutate({ url: ref.url, role }, { onSuccess: () => setOpen(false) })
    } catch {
      toast.error(t('video.uploadError'))
    } finally {
      setUploading(false)
    }
  }
  const addFromLibrary = (it) => add.mutate({ url: it.url, role: it.role, description: it.label }, { onSuccess: () => setOpen(false) })

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button variant="outline" size="sm" className="w-full">
          <Plus size={14} /> {t('video.addElement')}
        </Button>
      </PopoverTrigger>
      <PopoverContent align="center" className="w-80">
        <div className="mb-2.5 flex gap-1 rounded-lg border border-border bg-surface-muted/40 p-0.5">
          {[['upload', t('video.upload'), Upload], ['library', t('video.library'), Library]].map(([key, label, Icon]) => (
            <button
              key={key} type="button" onClick={() => setMode(key)}
              className={cn('inline-flex flex-1 items-center justify-center gap-1.5 rounded-md px-2 py-1 text-xs font-bold transition',
                mode === key ? 'bg-surface text-ink shadow-sm' : 'text-ink-muted hover:text-ink')}
            >
              <Icon size={13} /> {label}
            </button>
          ))}
        </div>

        {mode === 'upload' ? (
          <div>
            <SectionLabel className="mb-1 tracking-wider text-ink-secondary">{t('video.elementType')}</SectionLabel>
            <div className="mb-2.5 flex flex-wrap gap-1">
              {ADD_ROLES.map((r) => (
                <button
                  key={r.value} type="button" onClick={() => setRole(r.value)}
                  className={cn('rounded-full border px-2 py-0.5 text-[11px] font-semibold transition',
                    role === r.value ? 'border-brand bg-brand-soft text-brand' : 'border-border text-ink-muted hover:border-brand/40')}
                >
                  {r.label}
                </button>
              ))}
            </div>
            <input
              ref={fileRef} type="file" hidden onChange={pickFile}
              accept="image/jpeg,image/png,image/webp,video/mp4,video/quicktime,video/webm"
            />
            <Button
              size="sm" className="w-full" disabled={uploading || add.isPending}
              onClick={() => fileRef.current?.click()}
            >
              {uploading || add.isPending ? <InlineSpinner size={14} /> : <Upload size={14} />}
              {t('video.uploadFile')}
            </Button>
            <p className="mt-1.5 text-[11px] text-ink-muted">{t('video.uploadHint')}</p>
          </div>
        ) : (
          <div>
            {libLoading ? (
              <div className="flex justify-center py-6"><Spinner size={18} /></div>
            ) : items.length === 0 ? (
              <p className="py-6 text-center text-xs text-ink-muted">{t('video.libraryEmpty')}</p>
            ) : (
              <div className="grid max-h-64 grid-cols-3 gap-1.5 overflow-y-auto scrollbar-subtle">
                {items.map((it) => (
                  <button
                    key={it.url} type="button" onClick={() => addFromLibrary(it)} disabled={add.isPending}
                    title={t('video.addTitle', { label: it.label })}
                    className="group relative aspect-square overflow-hidden rounded-lg border border-border bg-brand-ink/90 transition hover:ring-2 hover:ring-brand disabled:opacity-50"
                  >
                    {it.kind === 'vid'
                      ? <video src={it.url} muted preload="metadata" className="size-full object-cover" />
                      : <img src={it.url} alt={it.label} className="size-full object-cover" />}
                    <span className="absolute inset-x-0 bottom-0 truncate bg-black/55 px-1 py-0.5 text-[9px] font-semibold text-white">{it.label}</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
      </PopoverContent>
    </Popover>
  )
}

// Map a video element (character, scenario, reference) to a lightbox slide.
function elementToMedia(item) {
  return urlToMedia(item.image_url, {
    id: item.key,
    name: item.role_label || i18n.t('ticket:video.elementCap'),
    caption: item.description || undefined,
  })
}

// The Elementos tab body: characters, scenarios, other references and the
// soundtrack — each addable, regeneratable and removable. Clicking an element's
// image opens it in the shared fullscreen media viewer.
function AssetsPanel({ creativeId, open }) {
  const { t } = useTranslation('ticket')
  const lightbox = useLightbox()
  const { data, isLoading } = useVideoAssets(creativeId, { enabled: open })
  const regen = useRegenerateAsset(creativeId)
  const remove = useRemoveAsset(creativeId)
  const confirm = useConfirm()
  const assets = data?.assets || {}
  const characters = assets.characters || []
  const scenarios = assets.scenarios || []
  const references = assets.references || []
  const music = assets.music
  const nothing = !isLoading && !characters.length && !scenarios.length && !references.length && !music
  const onRemove = async (item) => {
    const ok = await confirm({
      title: t('video.removeElementTitle'),
      description: t('video.removeElementDescription'),
      confirmLabel: t('actions.remove'),
      destructive: true,
    })
    if (ok) remove.mutate({ key: item.key })
  }

  // Every element image, in display order — the lightbox's slide list, so
  // opening one element lets you page through all of them.
  const imageItems = useMemo(
    () => [...characters, ...scenarios, ...references].filter((i) => i.image_url),
    [characters, scenarios, references],
  )
  const openImage = (item) => {
    const idx = imageItems.findIndex((i) => i.key === item.key)
    if (idx < 0) return
    lightbox.open(imageItems.map(elementToMedia), idx)
  }

  return (
    <div className="scrollbar-subtle min-h-0 flex-1 overflow-y-auto pr-1">
      {isLoading ? (
        <div className="flex justify-center py-16"><Spinner size={20} /></div>
      ) : (
        <div className="space-y-5">
          <AddElement creativeId={creativeId} />
          {nothing ? (
            <EmptyState icon={Boxes} title={t('video.noElements')} description={t('video.noElementsDescription')} color="#F43F5E" />
          ) : (
            <>
              <AssetSection title={t('video.characters')} icon={UserRound} items={characters} regenType="character" regen={regen} onRemove={onRemove} onOpen={openImage} />
              <AssetSection title={t('video.scenarios')} icon={ImageIcon} items={scenarios} regenType="scene" regen={regen} onRemove={onRemove} onOpen={openImage} />
              <AssetSection title={t('video.references')} icon={Boxes} items={references} regenType={null} regen={regen} onRemove={onRemove} onOpen={openImage} />
              {music && <MusicCard music={music} regen={regen} />}
            </>
          )}
        </div>
      )}
    </div>
  )
}

// The video editor: chat sidebar on the left; a continuous sequence player
// (global timecode across the scenes) + scene timeline as the main area.
// Editing is conversational — the agent decides which scenes to re-render.
// Videos render DRAFT-first; approving upgrades every scene to the final model.
export function VideoScenesDialog({ creative, open, onOpenChange }) {
  const { t } = useTranslation('ticket')
  const lightbox = useLightbox()
  const creativeId = creative?.id
  const { data, isLoading } = useVideoScenes(creativeId, { enabled: open })
  const chat = useVideoChat(creativeId)
  const finalize = useFinalizeVideo(creativeId)
  // Wallet balance shown in the header (null = unlimited/godfathered).
  const { data: creditsData } = useCredits()
  const creditBalance = creditsData?.wallet?.unlimited ? null : creditsData?.wallet?.available

  const scenes = data?.scenes || []
  const messages = data?.messages || []

  const [jumpTo, setJumpTo] = useState(null)
  // Per-scene annotations (keyed by 1-based scene number): a note text and/or
  // pinned media references ([{ url, kind }]). Set via the tile balloons, shown
  // as chips above the chat input, sent with the next message. A reference
  // pinned here goes STRAIGHT to that scene's render process (item 3).
  const [notes, setNotes] = useState([])
  const [playhead, setPlayhead] = useState(null)
  // Which tab is showing: the conversational editor or the assets list.
  const [tab, setTab] = useState('edicao')
  useEffect(() => { if (!open) { setNotes([]); setPlayhead(null); setTab('edicao') } }, [open])

  const noteFor = (scene) => notes.find((n) => n.scene === scene) || { text: '', refs: [] }
  // Upsert a scene's annotation; drop it entirely when it has neither text nor refs.
  const saveNote = (scene, text, refs = []) => setNotes((prev) => {
    const rest = prev.filter((n) => n.scene !== scene)
    return (text || refs.length) ? [...rest, { scene, text, refs }].sort((a, b) => a.scene - b.scene) : rest
  })
  const removeNote = (scene) => setNotes((prev) => prev.filter((n) => n.scene !== scene))

  // Deep-link: reflect the open creative in the URL (?creative=<id>) so it's
  // shareable and survives a reload; clear it on close.
  const [searchParams, setSearchParams] = useSearchParams()
  useEffect(() => {
    const next = new URLSearchParams(searchParams)
    if (open && creativeId) {
      if (next.get('creative') !== String(creativeId)) {
        next.set('creative', String(creativeId))
        setSearchParams(next, { replace: true })
      }
    } else if (!open && next.has('creative')) {
      next.delete('creative')
      setSearchParams(next, { replace: true })
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, creativeId])

  // INTERVIEW phase: the video hasn't been generated yet — the chat is gathering
  // context and decides when to build. No player/timeline until then.
  const interview = data?.creative?.metadata?.phase === 'interview'
  const generating = data?.creative?.status === 'generating' || (!data?.creative && creative?.status === 'generating')
  const failed = data?.creative?.status === 'failed' || scenes.some((s) => s.render_state === 'failed')
  const planning = generating && scenes.length === 0
  const busy = !failed && (generating || isBusy(scenes))
  const hasPlayable = scenes.some((s) => s.clip_url)
  const isDraft = (data?.creative?.metadata?.quality || 'final') === 'draft'
  const canUpgrade = isDraft && !busy && !failed && hasPlayable && !chat.isPending
  // High-quality render in flight (after approval, or an edit on a final video):
  // the old clips keep playing below as the live preview.
  const finalizing = !isDraft && busy && !failed && hasPlayable
  // The scenes actively being (re)rendered — names them in the progress banner.
  const workingNums = workingScenes(scenes).map((s) => s.position + 1)
  // The final composed file — ONE real video (continuous audio/motion). Only
  // when the creative is ready; while re-rendering, the clip-hop mode plays.
  const composedUrl = data?.creative?.status === 'ready' ? data?.creative?.asset_urls?.[0] : null

  // The cost of an edit is shown per-bubble (server stamps `credits` on the
  // assistant message) and the wallet counter refreshes — no floating pill.

  // The pinned per-scene notes go as STRUCTURED annotations
  // ([{ scene, note, reference_urls }]) alongside the message — never
  // concatenated into the text. The server maps each note + reference to its
  // scene; a pinned reference reaches that scene's render directly.
  // Chat attachments arrive as [{ url, kind, description }]; each note's pinned
  // refs the same. We split url + description into parallel arrays (what the
  // server expects) so the user's "what is this?" answer rides to the orchestrator.
  const send = (message, chatRefs = []) => {
    const annotations = notes.map((n) => ({
      scene: n.scene,
      note: n.text || '',
      reference_urls: (n.refs || []).map((r) => r.url),
      reference_descriptions: (n.refs || []).map((r) => r.description || ''),
    }))
    setNotes([])
    chat.mutate({
      message,
      referenceUrls: chatRefs.map((r) => r.url),
      referenceDescriptions: chatRefs.map((r) => r.description || ''),
      annotations,
    })
  }

  // The player box matches the video's real proportions; wide videos bind to
  // the width, tall/square ones to the height.
  const aspect = scenes[0]?.aspect_ratio || data?.creative?.metadata?.aspect_ratio || '9:16'
  const aspectCls = ASPECT_CLS[aspect] || ASPECT_CLS['9:16']

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-5xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Film size={18} className="text-[#F43F5E]" /> {t('video.editorTitle')}
          </DialogTitle>
          <DialogDescription className="flex items-center gap-1.5">
            <Sparkles size={13} className="text-emerald" />
            {interview
              ? t('video.interviewDescription')
              : t('video.editDescription')}
          </DialogDescription>
        </DialogHeader>

        {isLoading ? (
          <div className="flex justify-center py-16"><Spinner size={20} /></div>
        ) : interview ? (
          <div className="flex flex-col-reverse gap-4 sm:h-[min(72vh,46rem)] sm:flex-row">
            {/* Interview: just the chat + a waiting pane — no player yet. */}
            <div className="flex min-h-80 flex-col sm:min-h-0 sm:w-80 sm:shrink-0">
              <Chat
                messages={messages} notes={[]} onRemoveNote={() => {}} onSend={send}
                sending={chat.isPending} working={[]} creditBalance={creditBalance}
              />
            </div>
            <div className={cn('grid min-w-0 flex-1 place-items-center rounded-2xl border border-dashed border-border bg-surface-muted/20 p-8', aspectCls && '')}>
              <InterviewPane sending={chat.isPending} />
            </div>
          </div>
        ) : scenes.length === 0 && !generating ? (
          <EmptyState icon={Film} title={t('video.noScenes')} description={t('video.noScenesDescription')} color="#F43F5E" />
        ) : (
          <div className="flex flex-col gap-3 sm:h-[min(72vh,46rem)]">
            <TabBar tab={tab} onChange={setTab} />
            {tab === 'assets' ? (
              <AssetsPanel creativeId={creativeId} open={open} />
            ) : (
              <div className="flex min-h-0 flex-1 flex-col-reverse gap-4 sm:flex-row">
            {/* Left: chat — a full-height sidebar */}
            <div className="flex min-h-80 flex-col sm:min-h-0 sm:w-80 sm:shrink-0">
              <Chat
                messages={messages}
                notes={notes}
                onRemoveNote={removeNote}
                onSend={send}
                sending={chat.isPending}
                working={workingNums}
                creditBalance={creditBalance}
              />
            </div>

            {/* Right: player + timeline — the main area */}
            <div className="flex min-w-0 flex-1 flex-col gap-3">
              {/* Progress first: while anything is in flight, this is the clear
                  signal that the video is being worked on. */}
              <WorkBanner sending={chat.isPending} workingNums={workingNums} finalizing={finalizing} />
              {canUpgrade && (
                <div className="flex shrink-0 items-center justify-between gap-3 rounded-xl border border-brand/30 bg-brand-soft/40 px-3 py-2">
                  <p className="text-xs font-semibold text-ink">
                    <span className="text-brand">{t('video.quickPreview')}</span> {t('video.quickPreviewHint')}
                  </p>
                  <Button size="sm" className="h-8 shrink-0" disabled={finalize.isPending} onClick={() => finalize.mutate()}>
                    {finalize.isPending ? <InlineSpinner size={14} /> : <ArrowUpCircle size={14} />}
                    {t('video.highQuality')}
                  </Button>
                </div>
              )}

              <div className="flex min-h-72 flex-1 items-center justify-center sm:min-h-0">
                <div className={cn('max-h-full max-w-full', aspectCls, aspect === '16:9' ? 'w-full' : 'h-full')}>
                  {hasPlayable ? (
                    <SequencePlayer
                      scenes={scenes} composedUrl={composedUrl} music={data?.creative?.music}
                      jumpTo={jumpTo} onJumped={() => setJumpTo(null)}
                      onProgress={setPlayhead}
                      onFullscreen={composedUrl
                        ? () => lightbox.open(urlToMedia(composedUrl, { id: `video-${creativeId}`, name: t('video.videoName') }))
                        : undefined}
                    />
                  ) : (
                    <PreviewPlaceholder busy={busy} failed={failed} planning={planning} />
                  )}
                </div>
              </div>

              <div className="shrink-0">
                <SectionLabel className="mb-1.5 tracking-wider text-ink-secondary">
                  {t('video.scenesLabel')}
                </SectionLabel>
                {/* The locked identity + soundtrack are managed in the Assets tab
                    (or via the chat) — the scene strip stays focused on the shots. */}
                {planning ? (
                  <div className="flex gap-1.5">
                    {[0, 1, 2].map((i) => (
                      <Skeleton key={i} className="h-20 w-12 shrink-0 rounded-lg" />
                    ))}
                  </div>
                ) : (
                  <Timeline
                    scenes={scenes}
                    playhead={playhead}
                    noteFor={noteFor}
                    onSaveNote={saveNote}
                    onSeek={(s) => { if (s?.clip_url) setJumpTo(s.id) }}
                  />
                )}
              </div>
            </div>
              </div>
            )}
          </div>
        )}

      </DialogContent>
    </Dialog>
  )
}
