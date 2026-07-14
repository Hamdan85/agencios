// Visual tokens shared by the two ticket surfaces — the board card and the
// list row — so their chips and state rings never drift apart.
export const DUE_TONE = {
  danger: 'bg-danger/12 text-danger',
  warning: 'bg-amber/15 text-[#B45309]',
  muted: 'bg-surface-muted text-ink-muted',
}

// Client-approval state → a small chip on the card/row (labels live in
// ticket:row.approval.*). Only BLOCKED states get a chip — a resolved approval
// is implied by the ticket's column.
export const APPROVAL_CHIP_CLS = {
  pending: 'bg-amber/15 text-[#B45309]',
  changes_requested: 'bg-danger/12 text-danger',
}

// Executing on autopilot → a steady brand ring so the "working" ticket stands out.
export const AUTOPILOT_RING = 'border-brand/50 ring-1 ring-brand/40'
// Something broke at posting time → a danger ring (takes precedence).
export const ALERT_RING = 'border-danger/50 ring-1 ring-danger/40'

// The accent a ticket renders in: its project's color, else the caller's fallback.
export const projectAccent = (project, fallback = '#7C3AED') => project?.color || fallback
