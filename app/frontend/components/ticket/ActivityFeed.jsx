import { Card } from '@/components/ui/card'
import { EmptyState } from '@/components/ui/feedback'
import { Avatar } from '@/components/ui/avatar'
import { dt } from '@/lib/formatters'
import { attachmentKindMeta } from '@/lib/constants'
import CommentComposer from './CommentComposer'
import { MessageSquare, Sparkles, GitCommitHorizontal } from 'lucide-react'

const MENTION_RE = /@\[([^\]]+)\]\((\d+)\)/g

// Renders a comment body, turning `@[Name](id)` tokens into highlighted chips.
function renderBody(body) {
  const text = body || ''
  const nodes = []
  let last = 0
  let m
  MENTION_RE.lastIndex = 0
  while ((m = MENTION_RE.exec(text)) !== null) {
    if (m.index > last) nodes.push(text.slice(last, m.index))
    nodes.push(
      <span key={`m-${m.index}`} className="rounded px-0.5 font-semibold text-brand">
        @{m[1]}
      </span>,
    )
    last = m.index + m[0].length
  }
  if (last < text.length) nodes.push(text.slice(last))
  return nodes
}

// File chips for files attached to a comment (the same files also live in the
// ticket file list). Images show a thumbnail; everything else a typed icon.
function NoteAttachments({ attachments = [] }) {
  if (!attachments.length) return null
  return (
    <div className="mt-2 flex flex-wrap gap-2">
      {attachments.map((att) => {
        const meta = attachmentKindMeta(att.kind)
        const Icon = meta.icon
        const thumb = att.kind === 'image' ? att.preview_url || att.url : null
        return (
          <a
            key={att.id}
            href={att.url}
            target="_blank"
            rel="noreferrer"
            className="inline-flex max-w-full items-center gap-1.5 rounded-lg border border-border bg-surface py-1 pl-1.5 pr-2 text-[12px] text-ink-secondary transition hover:border-brand/40 hover:text-ink"
            title={att.display_name}
          >
            {thumb ? (
              <img src={thumb} alt="" className="size-5 shrink-0 rounded object-cover" />
            ) : (
              <span
                className="flex size-5 shrink-0 items-center justify-center rounded"
                style={{ background: `${meta.color}1F`, color: meta.color }}
              >
                <Icon size={12} strokeWidth={2.2} />
              </span>
            )}
            <span className="truncate">{att.display_name}</span>
          </a>
        )
      })}
    </div>
  )
}

// One entry in the timeline. System notes are subtle/grey, AI notes carry a
// brand tint + Sparkles, comments show the author avatar.
function NoteItem({ note }) {
  const kind = note?.kind || 'comment'

  if (kind === 'system') {
    return (
      <div className="flex items-start gap-2.5 px-1 py-2">
        <div className="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-surface-muted text-ink-muted">
          <GitCommitHorizontal size={15} />
        </div>
        <div className="flex-1 pt-0.5">
          <p className="text-[13px] leading-snug text-ink-muted">{note.body}</p>
          <p className="mt-0.5 text-[11px] text-ink-faint">{dt(note.created_at)}</p>
        </div>
      </div>
    )
  }

  if (kind === 'ai') {
    return (
      <div className="flex items-start gap-2.5 px-1 py-2">
        <div className="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-brand-gradient text-white shadow-sm">
          <Sparkles size={14} />
        </div>
        <div className="flex-1 rounded-2xl rounded-tl-sm border border-brand/20 bg-brand-soft/50 px-3 py-2">
          <div className="mb-0.5 flex items-center gap-1.5">
            <span className="text-xs font-bold text-brand">IA</span>
            <span className="text-[11px] text-ink-faint">{dt(note.created_at)}</span>
          </div>
          <p className="whitespace-pre-wrap text-[13px] leading-snug text-ink">{note.body}</p>
        </div>
      </div>
    )
  }

  // comment
  return (
    <div className="flex items-start gap-2.5 px-1 py-2">
      <Avatar name={note.user_name} src={note.user_avatar_url} size={28} className="mt-0.5" />
      <div className="flex-1">
        <div className="rounded-2xl rounded-tl-sm border border-border bg-surface px-3 py-2">
          <div className="mb-0.5 flex items-center gap-1.5">
            <span className="text-xs font-bold text-ink">{note.user_name || 'Membro'}</span>
            <span className="text-[11px] text-ink-faint">{dt(note.created_at)}</span>
          </div>
          {note.body && (
            <p className="whitespace-pre-wrap text-[13px] leading-snug text-ink-secondary">
              {renderBody(note.body)}
            </p>
          )}
          <NoteAttachments attachments={note.attachments} />
        </div>
      </div>
    </div>
  )
}

export default function ActivityFeed({ notes = [], onComment, posting = false }) {
  // Newest first.
  const items = [...(notes || [])].sort(
    (a, b) => new Date(b.created_at || 0) - new Date(a.created_at || 0),
  )

  return (
    <Card className="flex flex-col overflow-hidden">
      <div className="flex items-center gap-2 border-b border-border p-4">
        <div className="flex size-8 items-center justify-center rounded-xl" style={{ background: '#6366F118', color: '#6366F1' }}>
          <MessageSquare size={16} strokeWidth={2.3} />
        </div>
        <h3 className="font-display text-sm font-bold text-ink">Atividade</h3>
      </div>

      <div className="max-h-[420px] flex-1 overflow-y-auto px-3 no-scrollbar">
        {items.length === 0 ? (
          <div className="py-2">
            <EmptyState
              icon={MessageSquare}
              title="Sem atividade ainda"
              description="Comentários e o histórico do ticket aparecem aqui."
              color="#6366F1"
            />
          </div>
        ) : (
          <div className="divide-y divide-border/60">
            {items.map((n) => (
              <NoteItem key={n.id} note={n} />
            ))}
          </div>
        )}
      </div>

      <CommentComposer onSubmit={onComment} posting={posting} />
    </Card>
  )
}
