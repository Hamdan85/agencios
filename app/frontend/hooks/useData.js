// Barrel for the per-domain data hooks under hooks/data/. Existing imports
// (`import { useClients } from '@/hooks/useData'`) keep working unchanged —
// add new hooks to the matching domain module, not here.
// Note: hooks/data/shared.js (onErr, invalidateTicketSurfaces) is intentionally
// NOT re-exported; those are internal helpers, imported directly by the modules.
export * from './data/posts'
export * from './data/tickets'
export * from './data/workspace'
export * from './data/clients'
export * from './data/studio'
export * from './data/video'
export * from './data/settings'
