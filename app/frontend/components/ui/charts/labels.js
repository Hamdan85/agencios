// Localized display names for the metric series keys used across the charts, so
// a tooltip/legend never leaks a raw key ("views") when the surrounding copy is
// localized. Keys live in locales/<locale>/common.json (series.*); values resolve
// at access time so charts follow the active language. Keep in sync with
// PostMetric fields.
import i18n from '@/i18n'

const SERIES_KEYS = ['views', 'reach', 'engagement', 'likes', 'comments', 'shares', 'saves']

export const SERIES_LABELS = {}
for (const key of SERIES_KEYS) {
  Object.defineProperty(SERIES_LABELS, key, {
    get: () => i18n.t(`series.${key}`, { ns: 'common' }),
    enumerable: true,
  })
}

// The house color per series — the brand vocabulary the charts share (mirrors the
// LineTrend/metric palette). Identity follows the entity, never its rank.
export const SERIES_COLORS = {
  views: '#7C3AED',
  reach: '#0EA5E9',
  engagement: '#EC4899',
  likes: '#EC4899',
  comments: '#F59E0B',
  shares: '#10B981',
  saves: '#6366F1',
}

export const seriesLabel = (key) => SERIES_LABELS[key] || key
export const seriesColor = (key) => SERIES_COLORS[key] || '#7C3AED'
