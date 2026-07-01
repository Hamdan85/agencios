import { createContext, useCallback, useContext, useRef, useState } from 'react'
import { AlertTriangle } from 'lucide-react'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'

// A small confirmation modal for destructive / irreversible actions.
export function ConfirmDialog({
  open,
  onOpenChange,
  title = 'Tem certeza?',
  description,
  confirmLabel = 'Confirmar',
  cancelLabel = 'Cancelar',
  onConfirm,
  loading = false,
  destructive = false,
  icon: Icon = AlertTriangle,
  tone = '#F43F5E',
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <span
            className="mb-1 flex size-11 items-center justify-center rounded-2xl"
            style={{ background: `${tone}1A`, color: tone }}
          >
            <Icon size={22} strokeWidth={2.2} />
          </span>
          <DialogTitle>{title}</DialogTitle>
          {description && <DialogDescription>{description}</DialogDescription>}
        </DialogHeader>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={loading}>
            {cancelLabel}
          </Button>
          <Button
            variant={destructive ? 'destructive' : 'default'}
            onClick={onConfirm}
            disabled={loading}
          >
            {confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

export default ConfirmDialog

// ── Imperative API ──────────────────────────────────────────────────────────
// For the many one-off "are you sure?" spots (delete a project, cancel a
// subscription, archive a client…) a controlled open-state + local render is
// pure boilerplate. `useConfirm()` returns a promise-based `confirm(options)`
// that resolves to `true`/`false`, backed by a single shared dialog instance
// mounted once by `<ConfirmProvider>`. This replaces every `window.confirm`.
//
//   const confirm = useConfirm()
//   if (await confirm({ title: 'Excluir projeto?', destructive: true })) …
const ConfirmContext = createContext(null)

export function ConfirmProvider({ children }) {
  const [options, setOptions] = useState(null)
  const resolver = useRef(null)

  const confirm = useCallback((opts = {}) => (
    new Promise((resolve) => {
      resolver.current = resolve
      setOptions(opts)
    })
  ), [])

  const settle = useCallback((result) => {
    resolver.current?.(result)
    resolver.current = null
    setOptions(null)
  }, [])

  return (
    <ConfirmContext.Provider value={confirm}>
      {children}
      <ConfirmDialog
        {...options}
        open={options != null}
        onOpenChange={(next) => { if (!next) settle(false) }}
        onConfirm={() => settle(true)}
      />
    </ConfirmContext.Provider>
  )
}

// Returns `confirm(options) => Promise<boolean>`. Must be used under a
// <ConfirmProvider> (mounted at the app root).
export function useConfirm() {
  const confirm = useContext(ConfirmContext)
  if (!confirm) throw new Error('useConfirm must be used within a <ConfirmProvider>')
  return confirm
}
