// Media URL helpers shared by thumbnails and preview panels.
export const isVideoUrl = (url) => /\.(mp4|mov|webm)(\?|$)/i.test(url || '')
