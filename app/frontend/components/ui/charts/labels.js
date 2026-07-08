// Portuguese display names for the metric series keys used across the charts, so
// a tooltip/legend never leaks a raw English key ("views") when the surrounding
// copy already says "Visualizações". Keep in sync with PostMetric fields.
export const SERIES_LABELS = {
  views: 'Visualizações',
  reach: 'Alcance',
  engagement: 'Engajamento',
  likes: 'Curtidas',
  comments: 'Comentários',
  shares: 'Compartilhamentos',
  saves: 'Salvamentos',
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
