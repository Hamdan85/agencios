// The lightbox stacks ABOVE sheets/dialogs (it opens from the ticket drawer,
// the scenes editor, the studio). Closing it unmounts its Radix layer
// synchronously; on the deferred outside-press path (touch fires the custom
// event on `click`, after the unmount) the layer underneath re-checks the stack,
// finds itself topmost, and reads the press as its OWN outside-click — closing
// the drawer along with the lightbox. Target-based guard: a press that started
// inside the lightbox must never dismiss a layer below it. `closest` still works
// on the detached subtree after the unmount, which is exactly what makes this
// race-proof.
export function guardLightboxInteractOutside(handler) {
  return (event) => {
    if (event.target?.closest?.('[data-lightbox-root]')) {
      event.preventDefault()
      return
    }
    handler?.(event)
  }
}
