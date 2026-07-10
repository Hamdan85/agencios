import { useParams, Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { ArrowLeft, Hash, ImageOff } from 'lucide-react'
import { Page } from '@/components/ui/page'
import { Card } from '@/components/ui/card'
import { SectionLabel } from '@/components/ui/section-label'
import { Spinner, EmptyState } from '@/components/ui/feedback'
import { usePost } from '@/hooks/useData'
import CreativeExperience from '@/components/creative/CreativeExperience'
import PostDetailHeader from '@/components/posts/PostDetailHeader'
import PostDetailPerformance from '@/components/posts/PostDetailPerformance'

// Pull #hashtags off a caption so they can render as chips below the body.
function splitCaption(caption) {
  if (!caption) return { body: '', tags: [] }
  const tags = (caption.match(/#[\p{L}\p{N}_]+/gu) || []).map((t) => t.slice(1))
  return { body: caption, tags: [...new Set(tags)] }
}

// A single published/scheduled post: a network-colored hero with every linked
// entity, the creative rendered natively beside its caption, and the full
// performance panel (metric tiles + engagement donut + evolution chart).
// Reached from the /publicacoes grid.
export default function PostShow() {
  const { t } = useTranslation('posts')
  const { id } = useParams()
  const { data: post, isLoading } = usePost(id)

  if (isLoading) {
    return (
      <Page>
        <div className="flex min-h-[50vh] items-center justify-center">
          <Spinner size={30} />
        </div>
      </Page>
    )
  }

  if (!post) {
    return (
      <Page>
        <Link to="/publicacoes" className="mb-6 inline-flex items-center gap-1 text-sm font-medium text-ink-muted transition hover:text-ink">
          <ArrowLeft size={16} /> {t('show.back')}
        </Link>
        <EmptyState
          icon={ImageOff}
          title={t('show.notFound.title')}
          description={t('show.notFound.description')}
        />
      </Page>
    )
  }

  const { body, tags } = splitCaption(post.caption)

  return (
    <Page>
      <Link to="/publicacoes" className="mb-4 inline-flex items-center gap-1 text-sm font-medium text-ink-muted transition hover:text-ink">
        <ArrowLeft size={16} /> {t('show.back')}
      </Link>

      <PostDetailHeader post={post} />

      <div className="mt-5 grid grid-cols-1 gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)]">
        {/* Creative + caption */}
        <div className="space-y-4 animate-rise">
          {post.creative ? (
            <CreativeExperience creative={post.creative} />
          ) : (
            <div className="flex aspect-square w-full items-center justify-center rounded-2xl border border-border bg-surface-muted text-sm text-ink-muted">
              {t('show.noCreativePreview')}
            </div>
          )}

          {(body || tags.length > 0) && (
            <Card className="p-4 animate-rise">
              <SectionLabel className="mb-2 tracking-wide">{t('show.caption')}</SectionLabel>
              {body && <p className="whitespace-pre-wrap break-words text-sm leading-relaxed text-ink-secondary">{body}</p>}
              {tags.length > 0 && (
                <div className="mt-3 flex flex-wrap gap-1.5">
                  {tags.map((t, i) => (
                    <span key={i} className="inline-flex items-center gap-0.5 rounded-full bg-brand/10 px-2 py-0.5 text-[11px] font-semibold text-brand">
                      <Hash size={11} strokeWidth={2.5} />{t}
                    </span>
                  ))}
                </div>
              )}
            </Card>
          )}
        </div>

        {/* Performance */}
        <PostDetailPerformance metrics={post.metrics} history={post.metric_history} />
      </div>
    </Page>
  )
}
