import { toast } from 'sonner'
import { keys } from '@/api/queryKeys'

export const onErr = (msg) => (err) => toast.error(err?.error || msg)

// Invalidate the query surfaces a ticket can appear on. Every call refreshes
// the board; the options add the extra surfaces a given call site also touches:
//   ticketId    — that ticket's detail query (keys.ticket(id))
//   ticketsList — everything under the ['tickets'] prefix (global list + details)
//   projects    — project list/detail (ticket rollups on campaign pages)
// Each call site passes exactly the set it invalidated before this was factored
// out — don't grow or shrink an option without checking every caller.
export function invalidateTicketSurfaces(qc, { ticketId, ticketsList = false, projects = false } = {}) {
  if (ticketId) qc.invalidateQueries({ queryKey: keys.ticket(ticketId) })
  if (ticketsList) qc.invalidateQueries({ queryKey: ['tickets'] })
  qc.invalidateQueries({ queryKey: ['board'] })
  if (projects) qc.invalidateQueries({ queryKey: ['projects'] })
}
