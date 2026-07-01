import api from './client'

export const authApi = {
  me: () => api.get('/me'),
  login: (email, password) => api.post('/session', { email, password }),
  logout: () => api.delete('/session'),
  register: (data) => api.post('/registration', data),
  forgotPassword: (email) => api.post('/password_resets', { email }),
  resetPassword: (token, password) => api.put(`/password_resets/${token}`, { password }),
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
  get: (id) => api.get(`/tickets/${id}`),
  create: (data) => api.post('/tickets', { ticket: data }),
  update: (id, data) => api.patch(`/tickets/${id}`, { ticket: data }),
  destroy: (id) => api.delete(`/tickets/${id}`),
  advance: (id, toStatus, position) => api.post(`/tickets/${id}/advance`, { to_status: toStatus, position }),
  publish: (id, payload) => api.post(`/tickets/${id}/publish`, payload),
  reorder: (id, position) => api.patch(`/tickets/${id}/reorder`, { position }),
  summarize: (id) => api.post(`/tickets/${id}/summarize`),
  aiAction: (id) => api.post(`/tickets/${id}/ai_action`),
  generateSubtasks: (id) => api.post(`/tickets/${id}/generate_subtasks`),
  archive: (id) => api.post(`/tickets/${id}/archive`),
  unarchive: (id) => api.post(`/tickets/${id}/unarchive`),
  clearColumn: (status) => api.post('/tickets/clear_column', { status }),
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
  createPost: (id, data) => api.post(`/tickets/${id}/posts`, { post: data }),
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
  destroy: (id) => api.delete(`/clients/${id}`),
  synthesizePositioning: (data) => api.post('/clients/positioning_preview', data),
  extractFromUrl: (data) => api.post('/clients/extract_from_url', data),
  updatePositioning: (id, positioning) => api.patch(`/clients/${id}/positioning`, { positioning }),
  // Brand assets (logo / creator avatar) upload as multipart; either is optional.
  uploadBrandAssets: (id, { logo, defaultCreatorAvatar } = {}) => {
    const form = new FormData()
    if (logo) form.append('logo', logo)
    if (defaultCreatorAvatar) form.append('default_creator_avatar', defaultCreatorAvatar)
    return api.patch(`/clients/${id}/brand_assets`, form)
  },
}

export const projectsApi = {
  list: (params) => api.get('/projects', { params }),
  get: (id, params) => api.get(`/projects/${id}`, { params }),
  create: (data) => api.post('/projects', { project: data }),
  update: (id, data) => api.patch(`/projects/${id}`, { project: data }),
  destroy: (id) => api.delete(`/projects/${id}`),
  // Finalizes a project (→ `completed`) and kicks off its audit report.
  finalize: (id) => api.post(`/projects/${id}/finalize`),
}

// End-of-run project audit reports (the finalize deck).
export const reportsApi = {
  listByProject: (projectId) => api.get(`/projects/${projectId}/reports`),
  get: (id) => api.get(`/reports/${id}`),
}

export const studioApi = {
  get: () => api.get('/studio'),
  generate: (kind, params) => api.post('/studio/generate', { kind, params }),
}

export const creativesApi = {
  list: (params) => api.get('/creatives', { params }),
  update: (id, data) => api.patch(`/creatives/${id}`, { creative: data }),
  destroy: (id) => api.delete(`/creatives/${id}`),
}

export const generationsApi = {
  list: (params) => api.get('/generations', { params }),
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
  calendarAuthorizeUrl: () => api.get('/settings/google_calendar_authorize_url'),
  calendarDisconnect: () => api.delete('/settings/google_calendar'),
}

export const billingApi = {
  get: () => api.get('/billing'),
  changePlan: (plan) => api.post('/billing/change_plan', { plan }),
  cancel: () => api.post('/billing/cancel'),
  reactivate: () => api.post('/billing/reactivate'),
  checkout: (plan) => api.post('/billing/checkout_session', { plan }),
  portal: () => api.post('/billing/portal'),
}
