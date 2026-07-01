import { useState } from 'react'
import { Layers, MessageSquare } from 'lucide-react'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import AiSummaryCard from './AiSummaryCard'
import FieldGroup from './FieldGroup'
import PostingPanel from './PostingPanel'
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

  const showCreativesInMain = status === 'production'
  const saveFields = (fields) => mut.update.mutate({ status, fields })

  const main = (
    <div className="space-y-5">
      <AiSummaryCard
        status={status}
        summary={ticket.ai_summaries?.[status]}
        onSummarize={() => mut.summarize.mutate()}
        onAiAction={() => mut.aiAction.mutate()}
        summarizing={mut.summarize.isPending}
        acting={mut.aiAction.isPending}
      />
      {status === 'scheduled' ? (
        <PostingPanel
          ticket={ticket}
          creatives={creatives}
          posts={posts}
          onSave={saveFields}
          onPublish={(payload) => mut.publish.mutate(payload)}
          publishing={mut.publish.isPending}
        />
      ) : (
        <FieldGroup ticket={ticket} posts={posts} subtasks={subtasks} onSave={saveFields} saving={mut.update.isPending} />
      )}
      {(showCreativesInMain || creatives.length > 0) && (
        <CreativesPanel
          creatives={creatives}
          onGenerate={(payload) => mut.generate.mutate(payload)}
          generating={mut.generate.isPending}
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
