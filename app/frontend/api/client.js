import axios from 'axios'
import { toast } from 'sonner'

function getCsrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

const api = axios.create({
  baseURL: '/api/v1',
  headers: { 'Content-Type': 'application/json' },
  withCredentials: true,
})

api.interceptors.request.use((config) => {
  if (['post', 'put', 'patch', 'delete'].includes(config.method)) {
    config.headers['X-CSRF-Token'] = getCsrfToken()
  }
  // For file uploads, drop the JSON content-type so the browser sets the
  // multipart/form-data boundary itself (otherwise Rails can't parse it).
  if (typeof FormData !== 'undefined' && config.data instanceof FormData) {
    if (typeof config.headers.delete === 'function') config.headers.delete('Content-Type')
    else delete config.headers['Content-Type']
  }
  return config
})

// Login-less / public pages authenticate by a token in the path — a background
// 401 there (e.g. the analytics bridge probing `/me`) must NEVER bounce the
// visitor to /login, or the whole point of a shareable link is defeated.
const PUBLIC_PREFIXES = [
  '/portal/', '/aprovar/', '/conectar/', '/confirmar-troca-email/',
  '/redefinir-senha/', '/recuperar-senha', '/erro/',
]
const isPublicPath = (path) => PUBLIC_PREFIXES.some((p) => path.startsWith(p))

api.interceptors.response.use(
  (res) => res.data,
  (err) => {
    const status = err.response?.status
    const data = err.response?.data
    const path = window.location.pathname
    if (
      status === 401 &&
      !path.startsWith('/login') && !path.startsWith('/cadastro') &&
      path !== '/' && !isPublicPath(path)
    ) {
      window.location.href = '/login'
    }
    // Billing / credit gates. A 402 means either the workspace lost access
    // (paywall) or a single generation was blocked for lack of credits.
    if (status === 402) {
      if (data?.code === 'billing_required') {
        // The workspace is no longer billing-active — refresh `/me` so the
        // paywall guard (which reads workspace.billing_active) takes over.
        window.__queryClient?.invalidateQueries({ queryKey: ['me'] })
      } else if (data?.code === 'insufficient_credits') {
        toast.error('Créditos insuficientes', {
          description: 'Compre créditos para continuar gerando vídeos e imagens.',
          action: {
            label: 'Comprar créditos',
            onClick: () => { window.location.href = '/assinatura' },
          },
        })
      }
    }
    return Promise.reject(data ?? { error: err.message })
  },
)

export default api
