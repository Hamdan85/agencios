import { useState } from 'react'
import { Check, Copy } from 'lucide-react'
import { Button } from '@/components/ui/button'

// Copy-to-clipboard state: `copy(text)` writes and flips `copied` back after
// `resetMs`. Returns false when the clipboard is unavailable (insecure
// context) so callers can fall back.
export function useCopyToClipboard(resetMs = 1800) {
  const [copied, setCopied] = useState(false)
  const copy = async (text) => {
    try {
      await navigator.clipboard.writeText(String(text ?? ''))
      setCopied(true)
      setTimeout(() => setCopied(false), resetMs)
      return true
    } catch {
      return false
    }
  }
  return [copied, copy]
}

// Button that confirms the copy inline ("Copiar" → "Copiado!").
export function CopyButton({ value, label = 'Copiar', copiedLabel = 'Copiado!', ...props }) {
  const [copied, copy] = useCopyToClipboard()
  return (
    <Button onClick={() => copy(value)} variant={copied ? 'solid' : 'outline'} {...props}>
      {copied ? <><Check size={16} /> {copiedLabel}</> : <><Copy size={16} /> {label}</>}
    </Button>
  )
}
