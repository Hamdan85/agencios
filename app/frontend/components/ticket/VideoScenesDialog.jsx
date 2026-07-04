import { useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  Film, Loader2, RefreshCw, Check, AlertCircle, Sparkles, MessageSquare,
  Play, Pause, X, ArrowUpCircle, Download, ImagePlus, TriangleAlert, Coins, Pencil, Music,
} from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from '@/components/ui/dialog'
import { Popover, PopoverTrigger, PopoverContent } from '@/components/ui/popover'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/input'
import { Spinner, EmptyState } from '@/components/ui/feedback'
import { Bubble, TypingDots, ChatComposer } from '@/components/ui/chat'
import { Markdown } from '@/components/ui/markdown'
import { useVideoScenes, useVideoChat, useFinalizeVideo, useCredits } from '@/hooks/useData'
import { uploadsApi } from '@/api'
import { cn } from '@/lib/utils'

// Per-scene state → a solid icon dot on the thumb (label rides the tooltip),
// so the strip stays tiny and the player keeps the room. `working` states get a
// pulsing overlay so a queued scene never reads as idle.
const STATE_META = {
  ready:     { label: 'Pronta',       dot: 'bg-emerald text-white', icon: Check },
  rendering: { label: 'Renderizando', dot: 'bg-sky text-white',     icon: Loader2, spin: true, working: true },
  stale:     { label: 'Na fila',      dot: 'bg-amber text-white',   icon: Loader2, spin: true, working: true },
  fresh:     { label: 'Na fila',      dot: 'bg-amber text-white',   icon: Loader2, spin: true, working: true },
  failed:    { label: 'Falhou',       dot: 'bg-danger text-white',  icon: AlertCircle },
}

// The player box follows the video's real aspect — a 16:9 video in a fixed
// 9:16 box was a sliver with giant letterboxes.
const ASPECT_CLS = {
  '9:16': 'aspect-[9/16]', '1:1': 'aspect-square', '4:5': 'aspect-[4/5]', '16:9': 'aspect-video',
}

// Music-mood → PT label (fallback for a track with no title). Mirrors VideoConfig.
const MUSIC_MOOD_PT = {
  upbeat: 'Animada', calm: 'Calma', corporate: 'Corporativa', energetic: 'Energética',
  emotional: 'Emocional', epic: 'Épica', playful: 'Divertida', cinematic: 'Cinematográfica',
}

const WORKING_STATES = ['rendering', 'fresh', 'stale']
const isBusy = (scenes) => scenes.some((s) => WORKING_STATES.includes(s.render_state))
const workingScenes = (scenes) => scenes.filter((s) => WORKING_STATES.includes(s.render_state))

// "cena 2", "cenas 1 e 3", "cenas 1, 2 e 4" — for the progress banner copy.
const sceneList = (nums) => {
  const n = [...new Set(nums)].sort((a, b) => a - b)
  if (n.length === 0) return ''
  if (n.length === 1) return `cena ${n[0]}`
  return `cenas ${n.slice(0, -1).join(', ')} e ${n[n.length - 1]}`
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
function SequencePlayer({ scenes, composedUrl, music, jumpTo, onJumped, onProgress }) {
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
            type="button" onClick={play} aria-label="Tocar"
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
            {single && (
              <a
                href={`${composedUrl}${composedUrl.includes('?') ? '&' : '?'}disposition=attachment`}
                download
                title="Baixar o vídeo"
                className="inline-flex items-center gap-1 font-bold text-ink-secondary transition hover:text-ink"
              >
                <Download size={12} /> Baixar
              </a>
            )}
            <span>Cena {activeIdx + 1}/{segments.length}</span>
          </span>
        </div>
      </div>
    </div>
  )
}

// ── Placeholder when there's nothing playable yet ─────────────────────
function PreviewPlaceholder({ busy, failed, planning }) {
  return (
    <div className="grid size-full place-items-center rounded-2xl bg-brand-ink/90 text-white/70">
      {failed ? (
        <div className="flex flex-col items-center gap-2 px-4 text-center text-white/85">
          <AlertCircle size={26} className="text-danger" />
          <p className="text-sm font-semibold">A geração falhou</p>
          <p className="text-xs text-white/60">Peça no chat para refazer, ou gere o vídeo de novo.</p>
        </div>
      ) : busy ? (
        <div className="flex flex-col items-center gap-2 text-center">
          <Loader2 size={26} className="animate-spin" />
          <p className="text-xs">{planning ? 'Planejando as cenas…' : 'Renderizando o vídeo…'}</p>
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
            onSaveNote={(text) => onSaveNote(s.position + 1, text)}
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
  const m = STATE_META[s.render_state] || STATE_META.fresh
  const StateIcon = m.icon
  const [open, setOpen] = useState(false)
  const [draft, setDraft] = useState('')

  const openBalloon = () => { setDraft(note || ''); setOpen(true); onSeek() }
  const save = () => { onSaveNote(draft.trim()); setOpen(false) }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          type="button"
          title={`Cena ${s.position + 1} — anotar`}
          onClick={openBalloon}
          className={cn(
            'relative h-20 w-12 shrink-0 overflow-hidden rounded-lg border-2 text-left transition',
            open ? 'border-brand ring-2 ring-brand/20'
              : s.render_state === 'failed' ? 'border-danger/70'
              : note ? 'border-brand/50'
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
                <Loader2 size={16} className="animate-spin" />
              </div>
            )}
            <span className="absolute left-0.5 top-0.5 grid size-4 place-items-center rounded bg-black/60 text-[9px] font-bold text-white">
              {s.position + 1}
            </span>
            {/* A note badge, or the render-state dot when there's no note. */}
            {note ? (
              <span className="absolute right-0.5 top-0.5 grid size-4 place-items-center rounded-full bg-brand text-white shadow-sm">
                <Pencil size={9} />
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
        <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wider text-ink-secondary">
          Anotar a cena {s.position + 1}
        </p>
        <Textarea
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            // Single-line comment: Enter submits (Shift+Enter for a rare newline).
            if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); save() }
          }}
          placeholder="O que mudar nesta cena? (ex.: mais close, trocar o texto…)"
          rows={2}
          autoFocus
          className="min-h-12 text-sm"
        />
        <div className="mt-2 flex justify-end gap-2">
          {note && (
            <Button size="sm" variant="ghost" className="h-8" onClick={() => { onSaveNote(''); setOpen(false) }}>
              Remover
            </Button>
          )}
          <Button size="sm" className="h-8" onClick={save} disabled={!draft.trim()}>
            <Check size={14} /> Salvar
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

// The reward shown when an edit lands — light, iconographic, self-dismissing.
// Leads with the ready state, then the cost as a clear "−N créditos" badge.
function CreditReward({ credits }) {
  return (
    <div className="flex animate-rise justify-center py-1">
      <div className="inline-flex items-center gap-2 rounded-full bg-gradient-to-r from-emerald/15 to-brand/15 px-3 py-1.5 text-xs font-bold text-ink shadow-sm ring-1 ring-emerald/20">
        <span className="grid size-5 place-items-center rounded-full bg-emerald/20 text-emerald"><Check size={12} strokeWidth={3} /></span>
        Cena pronta! <Sparkles size={13} className="text-brand" />
        <span className="inline-flex items-center gap-1 rounded-full bg-amber/15 px-2 py-0.5 text-[#B45309]">
          <Coins size={12} /> −{credits} {credits === 1 ? 'crédito' : 'créditos'}
        </span>
      </div>
    </div>
  )
}

// ── Chat: talk to the whole video; scene notes + attached reference images
// buffer up and ride along with the next message ───────────────────────
const MAX_CHAT_REFS = 3

function Chat({ messages, notes, onRemoveNote, onSend, sending, working = [], creditDone = null }) {
  const [text, setText] = useState('')
  const [refs, setRefs] = useState([]) // [{ url }] attached reference images
  const [uploading, setUploading] = useState(false)
  const scrollRef = useRef(null)
  const fileRef = useRef(null)

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' })
  }, [messages, sending, working.length, creditDone])

  const pickRefs = async (e) => {
    const files = Array.from(e.target.files || [])
    e.target.value = ''
    if (!files.length) return
    const room = MAX_CHAT_REFS - refs.length
    if (room <= 0) { toast.error(`Máximo de ${MAX_CHAT_REFS} imagens.`); return }
    setUploading(true)
    try {
      const { reference_images: uploaded } = await uploadsApi.referenceImages(files.slice(0, room))
      setRefs((prev) => [...prev, ...uploaded].slice(0, MAX_CHAT_REFS))
    } catch {
      toast.error('Não foi possível enviar a imagem. Tente JPG, PNG ou WEBP.')
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
    // annotations get applied.
    onSend(msg || (hasNotes ? 'Aplique as anotações das cenas.' : 'Use esta referência.'), refs.map((r) => r.url))
    setText('')
    setRefs([])
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col rounded-2xl border border-border bg-surface-muted/30">
      <div ref={scrollRef} className="scrollbar-subtle min-h-0 flex-1 space-y-3 overflow-y-auto p-3">
        {messages.length === 0 ? (
          <div className="flex h-full flex-col items-center justify-center gap-2 px-4 text-center text-ink-muted">
            <MessageSquare size={22} className="text-brand" />
            <p className="text-sm font-semibold text-ink">Converse com o vídeo</p>
            <p className="text-xs">Diga o que quer mudar — no vídeo todo ou numa cena. Clique numa cena para anotar algo específico dela; as anotações vão junto com a mensagem.</p>
          </div>
        ) : (
          messages.map((m, i) => (
            m.kind === 'alert'
              ? <AlertMessage key={i} content={m.content} />
              : <Bubble key={i} role={m.role} content={m.content} />
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
              <Loader2 size={13} className="shrink-0 animate-spin" />
              Trabalhando {working.length === 1 ? 'na' : 'nas'} {sceneList(working)}… leva 1–2 min {working.length === 1 ? '' : 'cada'}.
            </div>
          </div>
        )}
        {/* The reward: shown only when the edit lands — light, iconographic. */}
        {creditDone && <CreditReward credits={creditDone.credits} />}
      </div>

      <div className="border-t border-border p-2.5">
        {/* Scene annotations (set on the tiles) — sent with the next message.
            Removable here; editable by clicking the scene again. */}
        {hasNotes && (
          <div className="mb-1.5 flex flex-wrap items-center gap-1.5">
            {notes.map((n) => (
              <span key={n.scene} className="inline-flex max-w-full items-center gap-1 rounded-full bg-brand-soft/60 px-2 py-0.5 text-[11px] font-semibold text-brand">
                <Pencil size={10} className="shrink-0" />
                <span className="truncate">Cena {n.scene}: {n.text}</span>
                <button type="button" onClick={() => onRemoveNote(n.scene)} aria-label="Remover nota" className="shrink-0 opacity-70 hover:opacity-100">
                  <X size={11} />
                </button>
              </span>
            ))}
          </div>
        )}
        {/* Attached reference images — ride along with the next message */}
        {refs.length > 0 && (
          <div className="mb-1.5 flex flex-wrap items-center gap-1.5">
            {refs.map((r, i) => (
              <div key={r.url} className="relative size-11 overflow-hidden rounded-lg border border-border">
                <img src={r.url} alt="Referência" className="size-full object-cover" />
                <button
                  type="button" onClick={() => setRefs((prev) => prev.filter((_, j) => j !== i))}
                  aria-label="Remover" className="absolute right-0.5 top-0.5 grid size-4 place-items-center rounded bg-black/60 text-white"
                >
                  <X size={10} />
                </button>
              </div>
            ))}
          </div>
        )}
        <input ref={fileRef} type="file" accept="image/jpeg,image/png,image/webp" multiple hidden onChange={pickRefs} />
        <div className="flex items-stretch gap-1.5">
          <button
            type="button" onClick={() => fileRef.current?.click()}
            disabled={sending || uploading || refs.length >= MAX_CHAT_REFS}
            title="Anexar imagem de referência"
            className="grid h-[52px] w-11 shrink-0 place-items-center rounded-xl border border-border text-ink-muted transition hover:border-brand hover:text-brand disabled:opacity-40"
          >
            {uploading ? <Loader2 size={16} className="animate-spin" /> : <ImagePlus size={16} />}
          </button>
          <div className="min-w-0 flex-1">
            <ChatComposer
              value={text}
              onChange={setText}
              onSend={submit}
              sending={sending}
              placeholder={
                refs.length ? 'Diga como usar a referência…'
                  : hasNotes ? 'Escreva ou envie só as anotações…'
                    : 'O que você quer mudar no vídeo?'
              }
            />
          </div>
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
  if (!sending && workingNums.length === 0) return null

  let text
  if (sending && workingNums.length === 0) {
    text = 'Aplicando o que você pediu…'
  } else if (finalizing) {
    text = `Renderizando em alta qualidade (${sceneList(workingNums)}) — a prévia continua tocando abaixo.`
  } else {
    const one = workingNums.length === 1
    text = `Trabalhando ${one ? 'na' : 'nas'} ${sceneList(workingNums)}… leva 1–2 min ${one ? 'por cena' : 'cada'}.`
  }

  return (
    <div className="shrink-0 overflow-hidden rounded-xl border border-brand/30 bg-brand-soft/40">
      <div className="flex items-center gap-2 px-3 py-2 text-xs font-semibold text-ink">
        <Loader2 size={14} className="shrink-0 animate-spin text-brand" />
        {text}
      </div>
      {/* Indeterminate sweep — motion the eye catches even from the chat side. */}
      <div className="h-0.5 w-full overflow-hidden bg-brand/15">
        <div className="anim-indeterminate h-full w-1/3 rounded-full bg-brand" />
      </div>
    </div>
  )
}

// The video editor: chat sidebar on the left; a continuous sequence player
// (global timecode across the scenes) + scene timeline as the main area.
// Editing is conversational — the agent decides which scenes to re-render.
// Videos render DRAFT-first; approving upgrades every scene to the final model.
export function VideoScenesDialog({ creative, open, onOpenChange }) {
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
  // Per-scene annotations (keyed by 1-based scene number): set via the tile
  // balloons, shown as chips above the chat input, sent with the next message.
  const [notes, setNotes] = useState([])
  const [playhead, setPlayhead] = useState(null)
  useEffect(() => { if (!open) { setNotes([]); setPlayhead(null) } }, [open])

  const noteFor = (scene) => notes.find((n) => n.scene === scene)?.text || ''
  const saveNote = (scene, text) => setNotes((prev) => {
    const rest = prev.filter((n) => n.scene !== scene)
    return text ? [...rest, { scene, text }].sort((a, b) => a.scene - b.scene) : rest
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

  // Credits are shown AFTER the edit lands, as a light celebratory pill — not
  // up front. `pendingCredit` holds the charged amount until the render settles;
  // `creditDone` is the brief reward shown when it finishes (auto-dismissed).
  const [pendingCredit, setPendingCredit] = useState(0)
  const [creditDone, setCreditDone] = useState(null)
  const prevBusy = useRef(false)
  useEffect(() => {
    if (prevBusy.current && !busy && pendingCredit > 0 && !failed) {
      setCreditDone({ credits: pendingCredit })
      setPendingCredit(0)
    }
    if (failed) setPendingCredit(0) // failed renders refund; the alert covers it
    prevBusy.current = busy
  }, [busy, failed, pendingCredit])
  useEffect(() => {
    if (!creditDone) return undefined
    const t = setTimeout(() => setCreditDone(null), 5000)
    return () => clearTimeout(t)
  }, [creditDone])
  useEffect(() => { if (!open) { setPendingCredit(0); setCreditDone(null) } }, [open])

  const send = (message, referenceUrls = []) => {
    const noteLines = notes.map((n) => `- Cena ${n.scene}: ${n.text}`).join('\n')
    const full = notes.length ? `Notas por cena:\n${noteLines}\n\n${message}` : message
    setNotes([])
    chat.mutate({ message: full, referenceUrls }, {
      onSuccess: (data) => {
        if (data?.action === 'edit' && data?.credits_spent > 0) setPendingCredit(data.credits_spent)
      },
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
            <Film size={18} className="text-[#F43F5E]" /> Editor de vídeo
            {/* Wallet balance — always visible so the cost of an edit is never a surprise. */}
            <span className="ml-auto inline-flex items-center gap-1 rounded-full bg-amber/10 px-2.5 py-1 text-xs font-bold text-[#B45309]">
              <Coins size={13} /> {creditBalance === null ? '∞' : `${creditBalance ?? '—'}`}
              <span className="font-semibold text-ink-muted">créditos</span>
            </span>
          </DialogTitle>
          <DialogDescription className="flex items-center gap-1.5">
            <Sparkles size={13} className="text-emerald" />
            Converse para editar. Clique numa cena para anotar; as anotações vão juntas na próxima mensagem.
          </DialogDescription>
        </DialogHeader>

        {isLoading ? (
          <div className="flex justify-center py-16"><Spinner size={20} /></div>
        ) : scenes.length === 0 && !generating ? (
          <EmptyState icon={Film} title="Sem cenas" description="Este vídeo não tem cenas editáveis." color="#F43F5E" />
        ) : (
          <div className="flex flex-col-reverse gap-4 sm:h-[min(72vh,46rem)] sm:flex-row">
            {/* Left: chat — a full-height sidebar */}
            <div className="flex min-h-80 flex-col sm:min-h-0 sm:w-80 sm:shrink-0">
              <Chat
                messages={messages}
                notes={notes}
                onRemoveNote={removeNote}
                onSend={send}
                sending={chat.isPending}
                working={workingNums}
                creditDone={creditDone}
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
                    <span className="text-brand">Prévia rápida.</span> Gostou? Gere a versão final — aqui ou pedindo no chat.
                  </p>
                  <Button size="sm" className="h-8 shrink-0" disabled={finalize.isPending} onClick={() => finalize.mutate()}>
                    {finalize.isPending ? <Loader2 size={14} className="animate-spin" /> : <ArrowUpCircle size={14} />}
                    Alta qualidade
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
                    />
                  ) : (
                    <PreviewPlaceholder busy={busy} failed={failed} planning={planning} />
                  )}
                </div>
              </div>

              <div className="shrink-0">
                <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wider text-ink-secondary">
                  Cenas · clique para anotar
                </p>
                {/* One continuous royalty-free track, burned into the final —
                    picked by the storyboard; changed only when asked in the chat. */}
                {data?.creative?.music?.url && (
                  <p className="mb-1.5 flex items-center gap-1 text-[11px] text-ink-muted">
                    <Music size={12} className="shrink-0 text-brand" />
                    Trilha: <span className="font-semibold text-ink-secondary">{data.creative.music.title || MUSIC_MOOD_PT[data.creative.music.mood] || 'música de fundo'}</span>
                    <span className="text-ink-faint">· peça no chat para trocar</span>
                  </p>
                )}
                {planning ? (
                  <div className="flex gap-1.5">
                    {[0, 1, 2].map((i) => (
                      <div key={i} className="h-20 w-12 shrink-0 animate-pulse rounded-lg bg-surface-muted" />
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
      </DialogContent>
    </Dialog>
  )
}
