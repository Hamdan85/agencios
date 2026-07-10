import { useEffect } from 'react'
import { useEditor, EditorContent } from '@tiptap/react'
import StarterKit from '@tiptap/starter-kit'
import Link from '@tiptap/extension-link'
import Placeholder from '@tiptap/extension-placeholder'
import { Bold, Italic, Strikethrough, List, ListOrdered, Link2, Heading2, Quote } from 'lucide-react'
import { cn } from '@/lib/utils'

// A single toolbar control.
function Tool({ active, disabled, onClick, title, children }) {
  return (
    <button
      type="button"
      title={title}
      aria-label={title}
      aria-pressed={active}
      disabled={disabled}
      onMouseDown={(e) => e.preventDefault()} // keep editor focus
      onClick={onClick}
      className={cn(
        'flex size-7 items-center justify-center rounded-lg text-ink-muted transition-colors',
        'hover:bg-surface-muted hover:text-ink disabled:opacity-40',
        active && 'bg-brand/12 text-brand',
      )}
    >
      {children}
    </button>
  )
}

function Toolbar({ editor }) {
  if (!editor) return null
  const setLink = () => {
    const prev = editor.getAttributes('link')?.href || ''
    const url = window.prompt('URL do link', prev)
    if (url === null) return
    if (url === '') { editor.chain().focus().extendMarkRange('link').unsetLink().run(); return }
    editor.chain().focus().extendMarkRange('link').setLink({ href: url }).run()
  }

  return (
    <div className="flex flex-wrap items-center gap-0.5 border-b border-border px-1.5 py-1">
      <Tool title="Negrito" active={editor.isActive('bold')} onClick={() => editor.chain().focus().toggleBold().run()}><Bold size={15} /></Tool>
      <Tool title="Itálico" active={editor.isActive('italic')} onClick={() => editor.chain().focus().toggleItalic().run()}><Italic size={15} /></Tool>
      <Tool title="Tachado" active={editor.isActive('strike')} onClick={() => editor.chain().focus().toggleStrike().run()}><Strikethrough size={15} /></Tool>
      <span className="mx-1 h-4 w-px bg-border" />
      <Tool title="Título" active={editor.isActive('heading', { level: 2 })} onClick={() => editor.chain().focus().toggleHeading({ level: 2 }).run()}><Heading2 size={15} /></Tool>
      <Tool title="Lista" active={editor.isActive('bulletList')} onClick={() => editor.chain().focus().toggleBulletList().run()}><List size={15} /></Tool>
      <Tool title="Lista numerada" active={editor.isActive('orderedList')} onClick={() => editor.chain().focus().toggleOrderedList().run()}><ListOrdered size={15} /></Tool>
      <Tool title="Citação" active={editor.isActive('blockquote')} onClick={() => editor.chain().focus().toggleBlockquote().run()}><Quote size={15} /></Tool>
      <span className="mx-1 h-4 w-px bg-border" />
      <Tool title="Link" active={editor.isActive('link')} onClick={setLink}><Link2 size={15} /></Tool>
    </div>
  )
}

// A Tiptap-backed rich text editor with a value(HTML)/onChange(html) contract,
// styled to match the design system (mirrors the Textarea surface). Used wherever
// formatted long-form content is wanted — see `<Textarea rich />`.
export function RichTextEditor({ value = '', onChange, onBlur, placeholder, className, disabled = false, minHeight = '6rem', autofocus = false }) {
  const editor = useEditor({
    immediatelyRender: false,
    editable: !disabled,
    autofocus: autofocus ? 'end' : false,
    extensions: [
      StarterKit.configure({ heading: { levels: [2, 3] } }),
      Link.configure({ openOnClick: false, autolink: true, HTMLAttributes: { class: 'text-brand underline' } }),
      Placeholder.configure({ placeholder: placeholder || 'Escreva…' }),
    ],
    content: value || '',
    editorProps: {
      attributes: {
        class: 'prose prose-sm max-w-none px-3.5 py-2.5 text-ink focus:outline-none',
        style: `min-height:${minHeight}`,
      },
    },
    onUpdate: ({ editor }) => onChange?.(editor.getHTML()),
    onBlur: () => onBlur?.(),
  })

  // Sync external value changes (e.g. parent reset / record switch) without
  // clobbering what the user is actively typing.
  useEffect(() => {
    if (!editor) return
    const current = editor.getHTML()
    if (value !== current && !editor.isFocused) {
      editor.commands.setContent(value || '', { emitUpdate: false })
    }
  }, [value, editor])

  useEffect(() => {
    if (editor) editor.setEditable(!disabled)
  }, [disabled, editor])

  return (
    <div
      className={cn(
        'overflow-hidden rounded-xl border border-border bg-surface-muted transition-colors',
        'focus-within:border-brand focus-within:bg-surface focus-within:ring-2 focus-within:ring-brand/20',
        disabled && 'cursor-not-allowed opacity-50',
        className,
      )}
    >
      <Toolbar editor={editor} />
      <EditorContent editor={editor} />
    </div>
  )
}

export default RichTextEditor
