// i18n bootstrap — all UI copy lives in app/frontend/locales/<locale>/<namespace>.json.
// pt-BR is the source language; en is the first target. Locale files are bundled
// eagerly (they're small); the active language comes from the authenticated /me
// payload (user.locale) and, before auth, from <html lang> / navigator.
import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'

const modules = import.meta.glob('./locales/*/*.json', { eager: true })
const resources = {}
for (const [path, mod] of Object.entries(modules)) {
  const [, locale, ns] = path.match(/\.\/locales\/([^/]+)\/([^/]+)\.json$/)
  ;(resources[locale] ??= {})[ns] = mod.default
}

export const AVAILABLE_LOCALES = ['pt-BR', 'en']

function initialLocale() {
  const html = document.documentElement.lang
  if (AVAILABLE_LOCALES.includes(html)) return html
  const nav = (navigator.language || '').toLowerCase()
  if (nav.startsWith('pt')) return 'pt-BR'
  if (nav.startsWith('en')) return 'en'
  return 'pt-BR'
}

i18n.use(initReactI18next).init({
  resources,
  lng: initialLocale(),
  fallbackLng: 'pt-BR',
  defaultNS: 'common',
  interpolation: { escapeValue: false }, // React already escapes
  returnNull: false,
})

// Switch the active UI language (called with user.locale from /me and by the
// locale picker). Keeps <html lang> in sync for a11y + CSS/date pickers.
export function applyLocale(locale) {
  if (!locale || !AVAILABLE_LOCALES.includes(locale) || i18n.language === locale) return
  i18n.changeLanguage(locale)
  document.documentElement.lang = locale
}

export default i18n
