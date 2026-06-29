import axios from 'axios'

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

api.interceptors.response.use(
  (res) => res.data,
  (err) => {
    const status = err.response?.status
    const path = window.location.pathname
    if (status === 401 && !path.startsWith('/login') && !path.startsWith('/cadastro') && path !== '/') {
      window.location.href = '/login'
    }
    return Promise.reject(err.response?.data ?? { error: err.message })
  },
)

export default api
