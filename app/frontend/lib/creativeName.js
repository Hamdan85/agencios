import { CREATIVE_TYPE_META } from '@/lib/constants'
import i18n from '@/i18n'

// Client-facing overrides where the internal label carries jargon
// (creativeName.* in locales/<locale>/common.json).
const CLIENT_LABEL_KEYS = ['ugc_video', 'thumbnail', 'cover']

// The label for a media-type slot (client-facing).
export function slotLabel(creativeType) {
  if (CLIENT_LABEL_KEYS.includes(creativeType)) {
    return i18n.t(`creativeName.${creativeType}`, { ns: 'common' })
  }
  return CREATIVE_TYPE_META[creativeType]?.label || creativeType
}

// "Opção A" / "Opção B" … for multi-option slots.
export function optionLabel(index) {
  return i18n.t('creativeName.option', { ns: 'common', letter: String.fromCharCode(65 + index) })
}

// A creative's display name: its own name if set, else the slot label; when the
// slot has several options, suffix the option letter so two "Imagem" become
// "Imagem · Opção A" / "Imagem · Opção B".
export function pieceName(creative, { index = 0, optionCount = 1 } = {}) {
  const base = creative?.name?.trim() || slotLabel(creative?.creative_type)
  return optionCount > 1 ? `${base} · ${optionLabel(index)}` : base
}

// Group a ticket's creatives into media-type slots, preserving encounter order.
// Returns [{ creativeType, label, options: [creative, …] }].
export function groupIntoSlots(creatives = []) {
  const order = []
  const byType = new Map()
  for (const c of creatives) {
    if (!byType.has(c.creative_type)) { byType.set(c.creative_type, []); order.push(c.creative_type) }
    byType.get(c.creative_type).push(c)
  }
  return order.map((creativeType) => ({
    creativeType,
    label: slotLabel(creativeType),
    options: byType.get(creativeType),
  }))
}
