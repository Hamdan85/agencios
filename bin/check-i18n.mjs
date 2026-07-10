#!/usr/bin/env node
// i18n guard: every t()/i18n.t() key referenced in the frontend must exist in
// locales/pt-BR/<ns>.json, and pt-BR/en key trees must match. Run: node bin/check-i18n.mjs
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'

const ROOT = new URL('..', import.meta.url).pathname
const FE = join(ROOT, 'app/frontend')
const LOCALES = join(FE, 'locales')

const walk = (dir) => readdirSync(dir).flatMap((f) => {
  const p = join(dir, f)
  if (statSync(p).isDirectory()) return f === 'locales' || f === 'node_modules' ? [] : walk(p)
  return /\.(jsx?|js)$/.test(f) ? [p] : []
})

const loadLocale = (locale) => {
  const dir = join(LOCALES, locale)
  const out = {}
  let files = []
  try { files = readdirSync(dir) } catch { return out }
  for (const f of files) {
    if (!f.endsWith('.json')) continue
    out[f.replace(/\.json$/, '')] = JSON.parse(readFileSync(join(dir, f), 'utf8'))
  }
  return out
}

const has = (obj, path) => {
  let cur = obj
  for (const part of path.split('.')) {
    if (cur == null || typeof cur !== 'object' || !(part in cur)) return false
    cur = cur[part]
  }
  return true
}

const hasKey = (ns, key, resources) => {
  const tree = resources[ns]
  if (!tree) return false
  return has(tree, key) || has(tree, `${key}_other`) || has(tree, `${key}_one`)
}

const ptBR = loadLocale('pt-BR')
const en = loadLocale('en')

let missing = []
for (const file of walk(FE)) {
  const src = readFileSync(file, 'utf8')
  const rel = relative(ROOT, file)
  // namespaces bound in this file (useTranslation('ns') / useTranslation(['a','b']))
  const nsMatches = [...src.matchAll(/useTranslation\(\s*\[?\s*['"]([\w-]+)['"]/g)].map((m) => m[1])
  const defaultNs = nsMatches[0] || 'common'
  for (const m of src.matchAll(/(?<![\w.$])(?:i18n\.)?t\(\s*(['"`])((?:(?!\1).)+)\1/g)) {
    const raw = m[2]
    if (raw.includes('${') || raw.includes(' ')) continue // dynamic/template or prose
    if (!/^[\w-]+(:[\w.-]+)?[\w.-]*$/.test(raw)) continue
    let ns = defaultNs
    let key = raw
    if (raw.includes(':')) [ns, key] = [raw.slice(0, raw.indexOf(':')), raw.slice(raw.indexOf(':') + 1)]
    if (!key.includes('.') && !resourcesHasNs(ns)) continue // likely not an i18n call
    if (!hasKey(ns, key, ptBR)) missing.push(`${rel}: pt-BR missing ${ns}:${key}`)
  }
}

function resourcesHasNs(ns) { return ns in ptBR || ns in en }

// parity: same key tree in both locales
const flat = (obj, prefix = '') => Object.entries(obj).flatMap(([k, v]) =>
  v && typeof v === 'object' ? flat(v, `${prefix}${k}.`) : [`${prefix}${k}`])
const parity = []
for (const ns of new Set([...Object.keys(ptBR), ...Object.keys(en)])) {
  const a = new Set(ns in ptBR ? flat(ptBR[ns]) : [])
  const b = new Set(ns in en ? flat(en[ns]) : [])
  for (const k of a) if (!b.has(k)) parity.push(`en missing ${ns}:${k}`)
  for (const k of b) if (!a.has(k)) parity.push(`pt-BR missing ${ns}:${k}`)
}

if (missing.length) {
  console.log(`\n── ${missing.length} referenced keys missing from pt-BR ──`)
  for (const m of missing) console.log('  ' + m)
}
if (parity.length) {
  console.log(`\n── ${parity.length} pt-BR/en parity gaps ──`)
  for (const m of parity.slice(0, 400)) console.log('  ' + m)
}
if (!missing.length && !parity.length) console.log('i18n check: OK')
process.exit(missing.length ? 1 : 0)
