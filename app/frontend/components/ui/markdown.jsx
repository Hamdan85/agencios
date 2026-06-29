import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import { cn } from '@/lib/utils'

// Renders a markdown string with the design-system "prose" styling. Used for
// AI-generated text (e.g. the contextual ticket summaries) that comes back as
// markdown so it shows formatted instead of as raw `#`/`**` source.
export function Markdown({ children, className }) {
  return (
    <div
      className={cn(
        'prose prose-sm max-w-none text-ink',
        'prose-headings:font-display prose-headings:font-bold prose-headings:text-ink prose-headings:mt-3 prose-headings:mb-1.5',
        'prose-p:my-1.5 prose-p:leading-relaxed prose-strong:text-ink prose-a:text-brand prose-a:no-underline hover:prose-a:underline',
        'prose-ul:my-1.5 prose-ol:my-1.5 prose-li:my-0.5 prose-blockquote:border-l-brand prose-blockquote:text-ink-secondary',
        className,
      )}
    >
      <ReactMarkdown remarkPlugins={[remarkGfm]}>{children || ''}</ReactMarkdown>
    </div>
  )
}

export default Markdown
