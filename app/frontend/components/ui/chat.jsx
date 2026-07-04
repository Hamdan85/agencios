import { Send, Loader2 } from 'lucide-react'
import { Textarea } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Markdown } from '@/components/ui/markdown'

// Shared chat primitives — the SAME look/behaviour across the strategist drawer
// and the video editor. User text is plain; the agent replies in markdown.

export function Bubble({ role, content, streaming }) {
  const isUser = role === 'user'
  return (
    <div className={`flex ${isUser ? 'justify-end' : 'justify-start'}`}>
      <div
        className={`max-w-[85%] cursor-text select-text rounded-2xl px-4 py-2.5 text-sm ${
          isUser ? 'whitespace-pre-wrap bg-brand text-white' : 'bg-surface-muted text-ink'
        }`}
      >
        {isUser
          ? content
          : <Markdown className="prose-p:first:mt-0 prose-p:last:mb-0">{content}</Markdown>}
        {streaming && <span className="ml-0.5 inline-block h-3.5 w-1.5 animate-pulse bg-current align-middle" />}
      </div>
    </div>
  )
}

// Three bouncing dots — the agent is "thinking" (waiting for the first token, or
// building a tool-call, which streams no visible text).
export function TypingDots() {
  return (
    <div className="flex justify-start">
      <div className="flex items-center gap-1 rounded-2xl bg-surface-muted px-4 py-3">
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            className="size-1.5 animate-bounce rounded-full bg-ink-faint"
            style={{ animationDelay: `${i * 0.16}s` }}
          />
        ))}
      </div>
    </div>
  )
}

// The composer: an auto-growing textarea + a send button that stays flush with
// it (self-stretch, fixed 52px square) — Enter sends, Shift+Enter breaks a line.
export function ChatComposer({
  value, onChange, onSend, sending = false, disabled = false, placeholder, inputRef, rows = 2, maxRows = 2,
}) {
  const canSend = value.trim().length > 0 && !sending && !disabled
  const fire = () => { if (canSend) onSend() }
  const onKeyDown = (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); fire() } }

  return (
    <form onSubmit={(e) => { e.preventDefault(); fire() }} className="flex items-stretch gap-2">
      <Textarea
        ref={inputRef}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={onKeyDown}
        rows={rows}
        maxRows={maxRows}
        placeholder={placeholder}
        className="h-[52px] flex-1 resize-none"
        disabled={disabled || sending}
      />
      <Button type="submit" className="h-auto w-[52px] shrink-0 self-stretch p-0" disabled={!canSend}>
        {sending ? <Loader2 size={18} className="animate-spin" /> : <Send size={18} />}
      </Button>
    </form>
  )
}
