// Route table mirror — keeps record ids and other dynamic segments out of any
// analytics event. Patterns mirror the React Router map in App.jsx (Portuguese
// segments). `maskPath('/clientes/abc123')` → '/clientes/:id'. Unknown paths
// collapse to '/*' so we never leak an unmapped, potentially PII-bearing URL.
//
// Order matters: more specific patterns (more segments) are matched first.
export const ROUTE_PATTERNS = [
  '/login',
  '/cadastro',
  '/painel',
  '/quadro',
  '/calendario',
  '/meu-calendario',
  '/tarefas',
  '/minhas-tarefas',
  '/projetos/:id',
  '/projetos',
  '/clientes/:id',
  '/clientes',
  '/tickets/:id/:tab',
  '/tickets/:id',
  '/estudio',
  '/reunioes',
  '/cobrancas',
  '/configuracoes',
  '/assinatura',
]

const compiled = ROUTE_PATTERNS
  .map((pattern) => ({
    pattern,
    segments: pattern.split('/').filter(Boolean),
  }))
  // Match deeper routes before their shallower prefixes.
  .sort((a, b) => b.segments.length - a.segments.length)

function matchPattern(parts, segments) {
  if (parts.length !== segments.length) return false
  return segments.every((seg, i) => seg.startsWith(':') || seg === parts[i])
}

export function maskPath(pathname) {
  if (!pathname || typeof pathname !== 'string') return '/*'

  // Drop query string + hash, then split into concrete segments.
  const clean = pathname.split('?')[0].split('#')[0]
  const parts = clean.split('/').filter(Boolean)

  if (parts.length === 0) return '/'

  const hit = compiled.find(({ segments }) => matchPattern(parts, segments))
  return hit ? hit.pattern : '/*'
}

export default maskPath
