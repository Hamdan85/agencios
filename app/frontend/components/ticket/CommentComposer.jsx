import { useMemo, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Textarea } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/feedback'
import { Avatar } from '@/components/ui/avatar'
import { useWorkspaceMembers } from '@/hooks/useData'
import { fileSize } from '@/lib/formatters'
import { cn } from '@/lib/utils'
import { Paperclip, Send, X, FileText } from 'lucide-react'

// Escapes a string for safe use inside a RegExp.
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

// Converts the human-typed body (mentions shown as plain `@Name`) into the
// stored token form `@[Name](id)`. Longer names first so `@Ana` never clobbers
// `@Ana Paula`; a trailing lookahead keeps us on word boundaries.
function toTokenBody(text, mentions) {
  let out = text
  const present = []
  ;[...mentions]
    .sort((a, b) => b.name.length - a.name.length)
    .forEach(({ userId, name }) => {
      const re = new RegExp(`@${escapeRe(name)}(?![\\p{L}\\p{N}_])`, 'gu')
      if (re.test(out)) {
        out = out.replace(re, `@[${name}](${userId})`)
        present.push(userId)
      }
    })
  return { body: out, mentionedUserIds: [...new Set(present)] }
}

// Reads the active `@query` immediately before the caret (anchored at an `@`
// that starts the string or follows whitespace). Returns null when not mentioning.
function activeMention(value, caret) {
  const upto = value.slice(0, caret)
  const at = upto.lastIndexOf('@')
  if (at === -1) return null
  const before = at === 0 ? '' : upto[at - 1]
  if (before && !/\s/.test(before)) return null
  const query = upto.slice(at + 1)
  if (/\s/.test(query)) return null
  return { start: at, query }
}

// The comment input: a plain textarea enriched with @-mention autocomplete and
// file attachments. Submits `{ body, mentionedUserIds, files }`.
export default function CommentComposer({ onSubmit, posting = false }) {
  const { t } = useTranslation('ticket')
  const { data: members = [] } = useWorkspaceMembers()
  const [text, setText] = useState('')
  const [mentions, setMentions] = useState([]) // { userId, name }
  const [files, setFiles] = useState([])
  const [mention, setMention] = useState(null) // { start, query }
  const [active, setActive] = useState(0)
  const [dragging, setDragging] = useState(false)
  const taRef = useRef(null)
  const fileRef = useRef(null)

  const suggestions = useMemo(() => {
    if (!mention) return []
    const q = mention.query.toLowerCase()
    return members
      .filter((m) => `${m.name} ${m.email}`.toLowerCase().includes(q))
      .slice(0, 6)
  }, [mention, members])

  const onTextChange = (e) => {
    const { value, selectionStart } = e.target
    setText(value)
    setMention(activeMention(value, selectionStart))
    setActive(0)
  }

  const pick = (member) => {
    if (!mention) return
    const before = text.slice(0, mention.start)
    const after = text.slice(mention.start + 1 + mention.query.length)
    const inserted = `@${member.name} `
    const next = `${before}${inserted}${after}`
    setText(next)
    setMentions((prev) =>
      prev.some((m) => m.userId === member.user_id)
        ? prev
        : [...prev, { userId: member.user_id, name: member.name }],
    )
    setMention(null)
    // Restore caret right after the inserted mention.
    const caret = before.length + inserted.length
    requestAnimationFrame(() => {
      const el = taRef.current
      if (el) {
        el.focus()
        el.setSelectionRange(caret, caret)
      }
    })
  }

  const addFiles = (list) => {
    const next = Array.from(list || []).filter(Boolean)
    if (next.length) setFiles((prev) => [...prev, ...next])
  }

  const removeFile = (idx) => setFiles((prev) => prev.filter((_, i) => i !== idx))

  const canSubmit = (text.trim() || files.length > 0) && !posting

  const submit = (e) => {
    e?.preventDefault()
    if (!canSubmit) return
    const { body, mentionedUserIds } = toTokenBody(text.trim(), mentions)
    onSubmit?.({ body, mentionedUserIds, files })
    setText('')
    setMentions([])
    setFiles([])
    setMention(null)
  }

  const onKeyDown = (e) => {
    if (mention && suggestions.length) {
      if (e.key === 'ArrowDown') {
        e.preventDefault()
        setActive((i) => (i + 1) % suggestions.length)
        return
      }
      if (e.key === 'ArrowUp') {
        e.preventDefault()
        setActive((i) => (i - 1 + suggestions.length) % suggestions.length)
        return
      }
      if (e.key === 'Enter' || e.key === 'Tab') {
        e.preventDefault()
        pick(suggestions[active])
        return
      }
      if (e.key === 'Escape') {
        setMention(null)
        return
      }
    }
    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') submit(e)
  }

  return (
    <form
      onSubmit={submit}
      className={cn('relative border-t border-border p-3', dragging && 'bg-brand-soft/40')}
      onDragOver={(e) => {
        e.preventDefault()
        setDragging(true)
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={(e) => {
        e.preventDefault()
        setDragging(false)
        addFiles(e.dataTransfer?.files)
      }}
    >
      {mention && suggestions.length > 0 && (
        <div className="absolute bottom-full left-3 right-3 mb-1 overflow-hidden rounded-xl border border-border bg-surface shadow-lg">
          {suggestions.map((m, i) => (
            <button
              key={m.id}
              type="button"
              onMouseDown={(e) => {
                e.preventDefault()
                pick(m)
              }}
              onMouseEnter={() => setActive(i)}
              className={cn(
                'flex w-full items-center gap-2 px-3 py-2 text-left transition',
                i === active ? 'bg-surface-muted' : 'hover:bg-surface-muted',
              )}
            >
              <Avatar name={m.name} src={m.avatar_url} size={24} />
              <div className="min-w-0">
                <p className="truncate text-[13px] font-semibold text-ink">{m.name}</p>
                <p className="truncate text-[11px] text-ink-faint">{m.email}</p>
              </div>
            </button>
          ))}
        </div>
      )}

      <Textarea
        ref={taRef}
        value={text}
        onChange={onTextChange}
        onKeyDown={onKeyDown}
        onPaste={(e) => {
          if (e.clipboardData?.files?.length) {
            e.preventDefault()
            addFiles(e.clipboardData.files)
          }
        }}
        placeholder={t('comment.placeholder')}
        rows={2}
        className="min-h-[60px]"
      />

      {files.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-2">
          {files.map((f, i) => (
            <span
              key={`${f.name}-${i}`}
              className="inline-flex max-w-full items-center gap-1.5 rounded-lg border border-border bg-surface-muted py-1 pl-2 pr-1 text-[12px] text-ink-secondary"
            >
              <FileText size={13} className="shrink-0 text-ink-muted" />
              <span className="truncate" title={f.name}>{f.name}</span>
              <span className="shrink-0 text-ink-faint">{fileSize(f.size)}</span>
              <button
                type="button"
                onClick={() => removeFile(i)}
                className="flex size-4 shrink-0 items-center justify-center rounded text-ink-muted transition hover:text-danger"
                aria-label={t('comment.removeFile', { name: f.name })}
              >
                <X size={13} />
              </button>
            </span>
          ))}
        </div>
      )}

      <input
        ref={fileRef}
        type="file"
        multiple
        className="hidden"
        onChange={(e) => {
          addFiles(e.target.files)
          e.target.value = ''
        }}
      />

      <div className="mt-2 flex items-center justify-between">
        <button
          type="button"
          onClick={() => fileRef.current?.click()}
          className="flex size-8 items-center justify-center rounded-lg text-ink-muted transition hover:bg-surface-muted hover:text-ink"
          aria-label={t('comment.attach')}
        >
          <Paperclip size={16} />
        </button>
        <Button type="submit" size="sm" disabled={!canSubmit}>
          {posting ? <Spinner size={14} className="border-white/30 border-t-white" /> : <Send size={14} />}
          {t('comment.submit')}
        </Button>
      </div>
    </form>
  )
}
