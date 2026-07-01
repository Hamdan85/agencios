import { useEffect, useState } from 'react'

// True once the browser has reported `offline` and stayed that way for a beat
// (avoids flashing the takeover page on momentary blips), false again as soon
// as `online` fires.
export function useOnlineStatus({ graceMs = 2500 } = {}) {
  const [offline, setOffline] = useState(false)

  useEffect(() => {
    let timer = null

    const handleOffline = () => {
      timer = setTimeout(() => setOffline(true), graceMs)
    }
    const handleOnline = () => {
      if (timer) clearTimeout(timer)
      setOffline(false)
    }

    window.addEventListener('offline', handleOffline)
    window.addEventListener('online', handleOnline)
    if (!navigator.onLine) handleOffline()

    return () => {
      if (timer) clearTimeout(timer)
      window.removeEventListener('offline', handleOffline)
      window.removeEventListener('online', handleOnline)
    }
  }, [graceMs])

  return offline
}

export default useOnlineStatus
