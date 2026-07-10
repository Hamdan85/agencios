import api from './client'

export const authApi = {
  me: () => api.get('/me'),
  login: (email, password) => api.post('/session', { email, password }),
  logout: () => api.delete('/session'),
  register: (data) => api.post('/registration', data),
  forgotPassword: (email) => api.post('/password_resets', { email }),
  // The reset service reads params[:token] (not the RESTful :id), so the token
  // rides in the body as well as the URL segment.
  resetPassword: (token, password) => api.put(`/password_resets/${token}`, { token, password }),
}

// The signed-in user's own account (profile, avatar, password, e-mail change).
export const accountApi = {
  update: (data) => api.patch('/account', { user: data }),
  updatePassword: (data) => api.patch('/account/password', data),
  updateAvatar: (file) => {
    const form = new FormData()
    form.append('avatar', file)
    return api.patch('/account/avatar', form)
  },
  changeEmail: (data) => api.post('/account/email', data),
  confirmEmailChange: (token) => api.post(`/account/email/confirm/${token}`),
  // Google Calendar is a personal integration — meetings are user-level.
  calendarAuthorizeUrl: () => api.get('/account/google_calendar_authorize_url'),
  calendarDisconnect: () => api.delete('/account/google_calendar'),
}

export const pushApi = {
  subscribe: (data) => api.post('/push_subscriptions', data),
  unsubscribe: (endpoint) => api.delete(`/push_subscriptions/${encodeURIComponent(endpoint)}`),
}

export const connectorApi = {
  get: () => api.get('/mcp_connector'),
  rotate: () => api.post('/mcp_connector/rotate'),
}

export const workspaceApi = {
  get: () => api.get('/workspace'),
  create: (data) => api.post('/workspace', { workspace: data }),
  update: (data) => api.patch('/workspace', { workspace: data }),
  switch: (workspaceId) => api.post('/workspace/switch', { workspace_id: workspaceId }),
  members: (params) => api.get('/workspace/memberships', { params }),
  updateMember: (id, role) => api.patch(`/workspace/memberships/${id}`, { role }),
  removeMember: (id) => api.delete(`/workspace/memberships/${id}`),
  invite: (email, role) => api.post('/workspace/invitations', { email, role }),
  acceptInvite: (token) => api.post(`/invitations/${token}/accept`),
}

export const dashboardApi = {
  get: () => api.get('/dashboard'),
}

// Authorized external apps (MCP connectors like Claude).
export const connectionsApi = {
  list: () => api.get('/connections'),
  revoke: (id) => api.delete(`/connections/${id}`),
}

export const boardApi = {
  get: (params) => api.get('/board', { params }),
}

export const ticketsApi = {
  list: (params) => api.get('/tickets', { params }),
  ids: (params) => api.get('/tickets/ids', { params }),
  get: (id) => api.get(`/tickets/${id}`),
  create: (data) => api.post('/tickets', { ticket: data }),
  update: (id, data) => api.patch(`/tickets/${id}`, { ticket: data }),
  destroy: (id) => api.delete(`/tickets/${id}`),
  advance: (id, toStatus, position) => api.post(`/tickets/${id}/advance`, { to_status: toStatus, position }),
  publish: (id, payload) => api.post(`/tickets/${id}/publish`, payload),
  requestApproval: (id) => api.post(`/tickets/${id}/request_approval`),
  approve: (id) => api.post(`/tickets/${id}/approve`),
  reorder: (id, position) => api.patch(`/tickets/${id}/reorder`, { position }),
  summarize: (id) => api.post(`/tickets/${id}/summarize`),
  aiAction: (id, payload) => api.post(`/tickets/${id}/ai_action`, payload),
  generateSubtasks: (id) => api.post(`/tickets/${id}/generate_subtasks`),
  archive: (id) => api.post(`/tickets/${id}/archive`),
  unarchive: (id) => api.post(`/tickets/${id}/unarchive`),
  clearColumn: (status) => api.post('/tickets/clear_column', { status }),
  bulkDestroy: (ids) => api.post('/tickets/bulk_destroy', { ticket_ids: ids }),
  createSubtask: (id, data) => api.post(`/tickets/${id}/subtasks`, { subtask: data }),
  // A comment carries optional @mentions (user ids) and file attachments, so it
  // is always sent as multipart FormData (the axios client strips the JSON
  // content-type when given a FormData body).
  createNote: (id, { body = '', mentionedUserIds = [], files = [] } = {}) => {
    const form = new FormData()
    form.append('note[body]', body)
    mentionedUserIds.forEach((uid) => form.append('note[mentioned_user_ids][]', uid))
    Array.from(files || []).forEach((file) => form.append('note[files][]', file))
    return api.post(`/tickets/${id}/notes`, form)
  },
  generateCreative: (id, payload) => api.post(`/tickets/${id}/creatives/generate`, payload),
  destroyCreative: (id, creativeId) => api.delete(`/tickets/${id}/creatives/${creativeId}`),
  // Manual upload — the file(s) become one Creative's assets.
  uploadCreative: (id, { creativeType, caption, files } = {}) => {
    const form = new FormData()
    form.append('creative_type', creativeType)
    if (caption) form.append('caption', caption)
    Array.from(files || []).forEach((file) => form.append('assets[]', file))
    return api.post(`/tickets/${id}/creatives`, form)
  },
  // Link an existing, unassigned Studio creative to this ticket.
  attachCreative: (id, creativeId) => api.post(`/tickets/${id}/creatives/attach`, { creative_id: creativeId }),
  createPost: (id, data) => api.post(`/tickets/${id}/posts`, { post: data }),
  unpublishPost: (id, postId) => api.post(`/tickets/${id}/posts/${postId}/unpublish`),
  // Cancel a scheduled (or failed) publication — removed before going live.
  destroyPost: (id, postId) => api.delete(`/tickets/${id}/posts/${postId}`),
  // Autopilot ("GO mode"): estimate the credit cost, then launch the run.
  autopilotEstimate: (id) => api.post(`/tickets/${id}/autopilot_estimate`),
  autopilotStart: (id, payload = {}) => api.post(`/tickets/${id}/autopilot_start`, payload),
}

export const subtasksApi = {
  update: (id, data) => api.patch(`/subtasks/${id}`, { subtask: data }),
  destroyNested: (ticketId, id) => api.delete(`/tickets/${ticketId}/subtasks/${id}`),
}

export const attachmentsApi = {
  // `files` is a FileList or array of File. One Attachment is created per file.
  create: (ticketId, files, meta = {}) => {
    const form = new FormData()
    const list = Array.from(files || [])
    if (list.length === 1) {
      form.append('file', list[0])
      if (meta.title) form.append('title', meta.title)
      if (meta.description) form.append('description', meta.description)
    } else {
      list.forEach((file) => form.append('files[]', file))
    }
    return api.post(`/tickets/${ticketId}/attachments`, form)
  },
  update: (ticketId, id, data) => api.patch(`/tickets/${ticketId}/attachments/${id}`, { attachment: data }),
  destroy: (ticketId, id) => api.delete(`/tickets/${ticketId}/attachments/${id}`),
}

export const tasksApi = {
  list: (params) => api.get('/tasks', { params }),
}

export const calendarApi = {
  get: (params) => api.get('/calendar', { params }),
}

export const clientsApi = {
  list: (params) => api.get('/clients', { params }),
  get: (id) => api.get(`/clients/${id}`),
  create: (data) => api.post('/clients', { client: data }),
  update: (id, data) => api.patch(`/clients/${id}`, { client: data }),
  archive: (id) => api.post(`/clients/${id}/archive`),
  unarchive: (id) => api.post(`/clients/${id}/unarchive`),
  rotatePortalLink: (id) => api.post(`/clients/${id}/rotate_portal_link`),
  destroy: (id) => api.delete(`/clients/${id}`),
  synthesizePositioning: (data) => api.post('/clients/positioning_preview', data),
  extractFromUrl: (data) => api.post('/clients/extract_from_url', data),
  updatePositioning: (id, positioning) => api.patch(`/clients/${id}/positioning`, { positioning }),
  // Brand assets (logo / creator avatar / carousel background) upload as
  // multipart; each is optional.
  uploadBrandAssets: (id, { logo, defaultCreatorAvatar, carouselBackground } = {}) => {
    const form = new FormData()
    if (logo) form.append('logo', logo)
    if (defaultCreatorAvatar) form.append('default_creator_avatar', defaultCreatorAvatar)
    if (carouselBackground) form.append('carousel_background', carouselBackground)
    return api.patch(`/clients/${id}/brand_assets`, form)
  },
  // Set the carousel background by copying an existing platform creative's image.
  setCarouselBackground: (id, creativeId) => api.post(`/clients/${id}/carousel_background`, { creative_id: creativeId }),
}

export const projectsApi = {
  list: (params) => api.get('/projects', { params }),
  get: (id, params) => api.get(`/projects/${id}`, { params }),
  create: (data) => api.post('/projects', { project: data }),
  update: (id, data) => api.patch(`/projects/${id}`, { project: data }),
  destroy: (id) => api.delete(`/projects/${id}`),
  // Starts a draft project (→ `active`).
  start: (id) => api.post(`/projects/${id}/start`),
  // Finalizes a project (→ `completed`) and kicks off its audit report.
  finalize: (id) => api.post(`/projects/${id}/finalize`),
  // Emails a read-only content-scope summary to the given addresses.
  sendScope: (id, recipients) => api.post(`/projects/${id}/send_scope`, { recipients }),
  // Autopilot ("GO mode") over the whole project — estimate then launch.
  autopilotEstimate: (id) => api.post(`/projects/${id}/autopilot_estimate`),
  autopilotStart: (id, payload = {}) => api.post(`/projects/${id}/autopilot_start`, payload),
  // Approval/publishing/scheduling config for the campaign (Configurações tab).
  updateSettings: (id, settings) => api.patch(`/projects/${id}/settings`, { settings }),
}

// Public client content approval (login-less; the path token is the credential).
// Per-client approval portal: one link → the client's queue of pending tickets.
export const approvalsApi = {
  get: (token) => api.get(`/public/client_approvals/${token}`),
  // Approve one media-type slot, choosing the winning option.
  approveSlot: (token, ticketId, { creativeType, creativeId }) =>
    api.post(`/public/client_approvals/${token}/tickets/${ticketId}/approve`, {
      creative_type: creativeType, creative_id: creativeId,
    }),
  requestChanges: (token, ticketId, { creativeId, feedback }) =>
    api.post(`/public/client_approvals/${token}/tickets/${ticketId}/request_changes`, {
      creative_id: creativeId, feedback,
    }),
  undo: (token, ticketId) =>
    api.post(`/public/client_approvals/${token}/tickets/${ticketId}/undo`),
}

// The login-less client central ("central do cliente"): the same token backs a
// full portal — campaign list + per-campaign read-only board, real-time metrics,
// and the finalized report.
export const portalApi = {
  get: (token) => api.get(`/public/portal/${token}`),
  board: (token, projectId) => api.get(`/public/portal/${token}/campaigns/${projectId}/board`),
  metrics: (token, projectId) => api.get(`/public/portal/${token}/campaigns/${projectId}/metrics`),
  report: (token, projectId) => api.get(`/public/portal/${token}/campaigns/${projectId}/report`),
}

// The posts hub: workspace-wide filterable list, a single post detail, and the
// analytics overview (KPIs + breakdowns) that heads the index page.
export const postsApi = {
  list: (params) => api.get('/posts', { params }),
  get: (id) => api.get(`/posts/${id}`),
  overview: (params) => api.get('/posts/overview', { params }),
}

// End-of-run project audit reports (the finalize deck).
export const reportsApi = {
  listByProject: (projectId) => api.get(`/projects/${projectId}/reports`),
  get: (id) => api.get(`/reports/${id}`),
  sendToClient: (id) => api.post(`/reports/${id}/send`),
}

export const studioApi = {
  get: () => api.get('/studio'),
  generate: (kind, params) => api.post('/studio/generate', { kind, params }),
  // Video opens as a chat INTERVIEW (no immediate generation) → { creative }.
  startVideo: (params) => api.post('/studio/video', { params }),
  // The "melhorar esse prompt" wand — returns { prompt } improved with the
  // client's brand + the current video setup as context.
  improvePrompt: (payload) => api.post('/studio/improve_prompt', payload),
}

export const uploadsApi = {
  // Upload media references (photos / short guide videos) →
  // [{ signed_id, url, kind: 'img' | 'vid' }]. Multipart FormData (the axios
  // client strips the JSON content-type for FormData bodies).
  references: (files = []) => {
    const form = new FormData()
    Array.from(files).forEach((f) => form.append('files[]', f))
    return api.post('/uploads/references', form)
  },
}

export const creativesApi = {
  list: (params) => api.get('/creatives', { params }),
  update: (id, data) => api.patch(`/creatives/${id}`, { creative: data }),
  destroy: (id) => api.delete(`/creatives/${id}`),
}

export const generationsApi = {
  list: (params) => api.get('/generations', { params }),
}

export const videoScenesApi = {
  list: (creativeId) => api.get(`/creatives/${creativeId}/scenes`),
  // { caption } is a free edit; { prompt } re-renders just this scene (charged).
  update: (id, data) => api.patch(`/video_scenes/${id}`, { scene: data }),
  // Conversational editor: send a message + optional attached media reference
  // URLs + the structured per-scene annotations ([{ scene, note }]); the agent
  // decides what to re-render.
  chat: (creativeId, { message, reference_image_urls = [], reference_descriptions = [], annotations = [] }) =>
    api.post(`/creatives/${creativeId}/video_chat`, { message, reference_image_urls, reference_descriptions, annotations }),
  // Approve the draft → re-render everything with the final (best) model.
  finalize: (creativeId) => api.post(`/creatives/${creativeId}/video_finalize`),
  // Elementos tab: the video's characters/scenarios/references/music.
  assets: (creativeId) => api.get(`/creatives/${creativeId}/assets`),
  // Reusable library elements to add (brand avatar/logo + other videos' refs).
  assetLibrary: (creativeId) => api.get(`/creatives/${creativeId}/assets/library`),
  // Regenerate ONE element from a prompt. type: 'character' | 'scene' | 'music';
  // ref_url identifies which existing image to replace (character/scene only).
  regenerateAsset: (creativeId, { type, prompt, ref_url }) =>
    api.post(`/creatives/${creativeId}/assets/regenerate`, { type, prompt, ref_url }),
  // Add an element (uploaded URL or a library asset) under a role.
  addAsset: (creativeId, { url, role, description }) =>
    api.post(`/creatives/${creativeId}/assets/add`, { url, role, description }),
  // Remove an element (a reference URL, or an "identity:<field>" key).
  removeAsset: (creativeId, { key }) =>
    api.post(`/creatives/${creativeId}/assets/remove`, { key }),
}

// Social networks are connected per CLIENT (the agency connects each client's
// own Instagram/TikTok/etc.), so every call is scoped to a client id.
export const socialApi = {
  list: (clientId) => api.get(`/clients/${clientId}/social_accounts`),
  authorizeUrl: (clientId, network) =>
    api.get(`/clients/${clientId}/social_accounts/authorize_url`, { params: { network } }),
  connectLink: (clientId) => api.get(`/clients/${clientId}/social_accounts/connect_link`),
  reconnect: (clientId, id) => api.post(`/clients/${clientId}/social_accounts/${id}/reconnect`),
  destroy: (clientId, id) => api.delete(`/clients/${clientId}/social_accounts/${id}`),
}

export const meetingsApi = {
  list: (params) => api.get('/meetings', { params }),
  create: (data) => api.post('/meetings', { meeting: data }),
  update: (id, data) => api.patch(`/meetings/${id}`, { meeting: data }),
  destroy: (id) => api.delete(`/meetings/${id}`),
}

export const invoicesApi = {
  list: (params) => api.get('/invoices', { params }),
  get: (id) => api.get(`/invoices/${id}`),
  create: (data) => api.post('/invoices', { invoice: data }),
  send: (id) => api.post(`/invoices/${id}/send_invoice`),
  cancel: (id) => api.post(`/invoices/${id}/cancel`),
  markPaid: (id) => api.post(`/invoices/${id}/mark_paid`),
  paymentLink: (id) => api.post(`/invoices/${id}/payment_link`),
  sendPaymentLink: (id) => api.post(`/invoices/${id}/send_payment_link`),
}

export const settingsApi = {
  get: () => api.get('/settings'),
  update: (data) => api.patch('/settings', data),
  // Brand assets (agency logo / creator avatar) upload as multipart; either is optional.
  uploadBrandAssets: ({ logo, defaultCreatorAvatar } = {}) => {
    const form = new FormData()
    if (logo) form.append('logo', logo)
    if (defaultCreatorAvatar) form.append('default_creator_avatar', defaultCreatorAvatar)
    return api.patch('/settings/brand_assets', form)
  },
}

export const billingApi = {
  get: () => api.get('/billing'),
  changePlan: (plan, interval = 'month') => api.post('/billing/change_plan', { plan, interval }),
  cancel: () => api.post('/billing/cancel'),
  reactivate: () => api.post('/billing/reactivate'),
  checkout: (plan, interval = 'month') => api.post('/billing/checkout_session', { plan, interval }),
  portal: () => api.post('/billing/portal'),
}

// Prepaid credit wallet (video/image generation) + top-up checkout.
export const creditsApi = {
  get: () => api.get('/credits'),
  usage: (params = {}) => api.get('/credits/usage', { params }),
  checkout: (pack) => api.post('/credits/checkout', { pack }),
}

// Public pricing catalog (unauthenticated): plans, packs, credit costs, trial.
export const pricingApi = {
  get: () => api.get('/pricing'),
}

// AI content-strategy planning: a chat that turns a monthly cadence into
// scheduled tickets. The chat turn STREAMS over SSE, so `streamMessage` uses a
// raw fetch + ReadableStream reader instead of axios (which buffers the body).
export const strategyApi = {
  show: (projectId) => api.get(`/projects/${projectId}/strategy_session`),
  start: (projectId) => api.post(`/projects/${projectId}/strategy_session`),
  apply: (sessionId) => api.post(`/strategy_sessions/${sessionId}/apply`),
  discard: (sessionId) => api.post(`/strategy_sessions/${sessionId}/discard`),

  // Send one message and stream the agent's reply. Calls `onDelta(text)` for
  // each text chunk, `onProposal(plan)` when a plan is proposed, and resolves
  // with `{ status }` on `done`. Rejects on an `error` SSE event.
  async streamMessage(sessionId, content, { onDelta, onProposal, onGenerating, signal } = {}) {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    const res = await fetch(`/api/v1/strategy_sessions/${sessionId}/messages`, {
      method: 'POST',
      credentials: 'include',
      signal,
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf || '' },
      body: JSON.stringify({ content }),
    })
    if (!res.ok || !res.body) throw new Error(`stream failed (${res.status})`)

    const reader = res.body.getReader()
    const decoder = new TextDecoder()
    let buffer = ''
    let done = { status: null }

    // Parse one `\n\n`-delimited SSE block into { event, data }.
    const parseBlock = (block) => {
      let event = 'message'
      let data = ''
      block.split('\n').forEach((line) => {
        if (line.startsWith('event:')) event = line.slice(6).trim()
        else if (line.startsWith('data:')) data += line.slice(5).trim()
      })
      return { event, data }
    }

    for (;;) {
      const { value, done: streamDone } = await reader.read()
      if (streamDone) break
      buffer += decoder.decode(value, { stream: true })
      let sep
      while ((sep = buffer.indexOf('\n\n')) !== -1) {
        const rawBlock = buffer.slice(0, sep)
        buffer = buffer.slice(sep + 2)
        if (!rawBlock.trim()) continue
        if (rawBlock.startsWith(':')) continue // keep-alive comment (heartbeat) — ignore
        const { event, data } = parseBlock(rawBlock)
        let payload = {}
        try { payload = data ? JSON.parse(data) : {} } catch { payload = {} }

        if (event === 'delta') onDelta?.(payload.text || '')
        else if (event === 'generating') onGenerating?.()
        else if (event === 'proposal') onProposal?.(payload.plan)
        else if (event === 'done') done = { status: payload.status }
        else if (event === 'error') throw new Error(payload.message || 'Erro no chat de estratégia.')
      }
    }
    return done
  },
}
