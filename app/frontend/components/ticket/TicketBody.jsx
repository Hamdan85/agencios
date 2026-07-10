import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { keys } from '@/api/queryKeys'
import { Layers, MessageSquare } from 'lucide-react'
import { useAiFillStatus } from '@/hooks/useRealtime'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import AiFillDialog from './AiFillDialog'
import FieldGroup from './FieldGroup'
import PostingPanel from './PostingPanel'
import ApprovalPanel from './ApprovalPanel'
import CreativesPanel from './CreativesPanel'
import AttachmentsPanel from './AttachmentsPanel'
import MetaCard from './MetaCard'
import SubtasksPanel from './SubtasksPanel'
import ActivityFeed from './ActivityFeed'

// The shared ticket detail content (everything below the header + stepper),
// reused by both the full-page view (Tickets/Show) and the board side drawer.
//
//   compact=false → desktop 2-column rail + mobile tabs (the page).
//   compact=true  → single-column tabbed, mobile-style (the drawer).
export default function TicketBody({
  id, status, ticket, subtasks = [], creatives = [], attachments = [], posts = [], notes = [], mut,
  compact = false, tab, onTabChange,
}) {
  // Local tab state for the compact (drawer) variant. Declared unconditionally.
  const [drawerTab, setDrawerTab] = useState('details')
  // "Atualizar com IA" opens a dialog asking what to change before regenerating.
  const [aiOpen, setAiOpen] = useState(false)
  // The rewrite runs off the request: the fields shimmer until the ticket channel
  // broadcasts it's done (useAiFillStatus). Set optimistically on submit so the
  // shimmer is instant, and rolled back if the enqueue itself fails.
  const [aiFilling, setAiFilling] = useAiFillStatus(id)

  const showCreativesInMain = status === 'production'
  const saveFields = (fields) => mut.update.mutate({ status, fields })
  // "Atualizar com IA" fills the current stage's fields — only meaningful on the
  // editable funnel stages (the read-only monitoring/done stages have no fields).
  const editable = !['published', 'done'].includes(status)
  const runAiFill = (instruction) => {
    setAiFilling(true)
    mut.aiAction.mutate({ instruction }, {
      onSuccess: () => setAiOpen(false),
      onError: () => setAiFilling(false),
    })
  }

  // Cancel a scheduled publication: confirmed, then the post is deleted before
  // it goes live (it can be scheduled again from this same step).
  const confirm = useConfirm()
  const qc = useQueryClient()
  const cancelPost = async (postId) => {
    const ok = await confirm({
      title: 'Cancelar agendamento?',
      description: 'O post não será publicado nesta rede. Você pode agendar de novo quando quiser.',
      confirmLabel: 'Cancelar agendamento',
      destructive: true,
    })
    if (ok) mut.removePost.mutate(postId)
  }

  const main = (
    <div className="space-y-5">
      {/* Client approval: actions in Produção; the "Aprovado por <actor>" badge
          persists in Publicação (scheduled) since full approval advanced it there. */}
      {(status === 'production' || (status === 'scheduled' && ticket.approval?.fully_approved)) && (
        <ApprovalPanel ticket={ticket} creatives={creatives} onChanged={() => qc.invalidateQueries({ queryKey: keys.ticket(id) })} />
      )}
      {status === 'scheduled' ? (
        <PostingPanel
          ticket={ticket}
          creatives={creatives}
          posts={posts}
          onSave={saveFields}
          onPublish={(payload) => mut.publish.mutate(payload)}
          publishing={mut.publish.isPending}
          onAiAction={() => setAiOpen(true)}
          acting={aiFilling}
          filling={aiFilling}
          onUnpublish={(postId) => mut.unpublishPost.mutate(postId)}
          unpublishingId={mut.unpublishPost.isPending ? mut.unpublishPost.variables : null}
          onCancelPost={cancelPost}
          cancelingId={mut.removePost.isPending ? mut.removePost.variables : null}
        />
      ) : (
        <FieldGroup
          ticket={ticket}
          posts={posts}
          subtasks={subtasks}
          onSave={saveFields}
          saving={mut.update.isPending}
          onAiAction={editable ? () => setAiOpen(true) : undefined}
          acting={aiFilling}
          filling={aiFilling}
          onUnpublish={(postId) => mut.unpublishPost.mutate(postId)}
          unpublishingId={mut.unpublishPost.isPending ? mut.unpublishPost.variables : null}
        />
      )}
      {/* In "Postagem" (scheduled) the PostingPanel already surfaces the creatives
          to post, so the full Criativos panel is hidden to avoid duplication. */}
      {status !== 'scheduled' && (showCreativesInMain || creatives.length > 0) && (
        <CreativesPanel
          creatives={creatives}
          creativeTypes={ticket.creative_types}
          channels={ticket.channels}
          onGenerate={(payload) => mut.generate.mutate(payload)}
          generating={mut.generate.isPending}
          onUpload={(payload) => mut.uploadCreative.mutate(payload)}
          uploading={mut.uploadCreative.isPending}
          onAttach={(creativeId) => mut.attachCreative.mutate(creativeId)}
          attaching={mut.attachCreative.isPending}
          onDelete={(creativeId) => mut.removeCreative.mutate(creativeId)}
          deleting={mut.removeCreative.isPending}
        />
      )}
      {/* Files are available in every workflow status. */}
      <AttachmentsPanel
        attachments={attachments}
        onUpload={(files) => mut.uploadAttachments.mutate({ files })}
        onRename={(payload) => mut.updateAttachment.mutate(payload)}
        onRemove={(attachmentId) => mut.removeAttachment.mutate(attachmentId)}
        uploading={mut.uploadAttachments.isPending}
      />
      <AiFillDialog
        open={aiOpen}
        onOpenChange={setAiOpen}
        onSubmit={runAiFill}
        pending={mut.aiAction.isPending}
      />
    </div>
  )

  const meta = <MetaCard ticket={ticket} onUpdate={(data) => mut.update.mutate(data)} />
  const subs = (
    <SubtasksPanel
      ticketId={id}
      subtasks={subtasks}
      onAdd={(payload) => mut.addSubtask.mutate(payload)}
      adding={mut.addSubtask.isPending}
      onGenerate={() => mut.generateSubtasks.mutate()}
      generating={mut.generateSubtasks.isPending}
    />
  )
  const activity = (
    <ActivityFeed
      notes={notes}
      onComment={(payload) => mut.addNote.mutate(payload)}
      posting={mut.addNote.isPending}
    />
  )

  const tabList = (
    <TabsList className="mb-4 w-full">
      <TabsTrigger value="details" className="flex-1"><Layers size={14} /> Detalhes</TabsTrigger>
      <TabsTrigger value="activity" className="flex-1"><MessageSquare size={14} /> Atividade</TabsTrigger>
    </TabsList>
  )

  // Compact: single column, tabbed, local state — the mobile-friendly shape.
  if (compact) {
    return (
      <Tabs value={drawerTab} onValueChange={setDrawerTab}>
        {tabList}
        <TabsContent value="details" className="space-y-5">
          {main}
          {meta}
          {subs}
        </TabsContent>
        <TabsContent value="activity">{activity}</TabsContent>
      </Tabs>
    )
  }

  // Page: desktop 2-column with a sticky rail; mobile falls back to tabs.
  return (
    <>
      <div className="hidden lg:grid lg:grid-cols-[1fr_360px] lg:items-start lg:gap-6">
        <div>{main}</div>
        <div className="lg:sticky lg:top-4">
          <div className="space-y-5">
            {meta}
            {subs}
            {activity}
          </div>
        </div>
      </div>

      <div className="lg:hidden">
        <Tabs defaultValue={tab === 'atividade' ? 'activity' : 'details'} onValueChange={onTabChange}>
          {tabList}
          <TabsContent value="details" className="space-y-5">
            {main}
            {meta}
            {subs}
          </TabsContent>
          <TabsContent value="activity">{activity}</TabsContent>
        </Tabs>
      </div>
    </>
  )
}
