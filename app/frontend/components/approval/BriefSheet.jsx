import { Sheet, SheetContent, SheetTitle } from '@/components/ui/sheet'

// The full briefing, in a Sheet that slides OVER the deck (bottom on mobile,
// right on desktop) — so opening it never pushes the approval actions off-screen.
export default function BriefSheet({ open, onOpenChange, ticket }) {
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="max-h-[80vh] overflow-y-auto rounded-t-2xl sm:max-w-lg">
        <SheetTitle className="mb-1">Briefing</SheetTitle>
        <p className="mb-4 text-sm text-ink-muted">{ticket?.title}</p>
        {ticket?.objective && (
          <div className="mb-4">
            <p className="mb-1 text-xs font-bold uppercase tracking-wide text-ink-faint">Objetivo</p>
            <p className="text-sm text-ink-secondary">{ticket.objective}</p>
          </div>
        )}
        {ticket?.brief && (
          <div>
            <p className="mb-1 text-xs font-bold uppercase tracking-wide text-ink-faint">Briefing completo</p>
            <p className="whitespace-pre-wrap text-sm text-ink-secondary">{ticket.brief}</p>
          </div>
        )}
      </SheetContent>
    </Sheet>
  )
}
