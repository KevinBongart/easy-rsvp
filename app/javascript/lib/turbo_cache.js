import Modal from "bootstrap/js/dist/modal"
import ScrollBarHelper from "bootstrap/js/src/util/scrollbar"

document.addEventListener("turbo:before-cache", () => {
  document.querySelectorAll(".modal.show").forEach((modal) => {
    // dispose() removes Bootstrap's listeners and instance data, but it does
    // not hide an open modal. Clean up its visible state before Turbo snapshots it.
    Modal.getInstance(modal)?.dispose()
    modal.classList.remove("show")
    modal.style.display = "none"
    modal.setAttribute("aria-hidden", "true")
    modal.removeAttribute("aria-modal")
    modal.removeAttribute("role")
    modal.style.removeProperty("padding-left")
    modal.style.removeProperty("padding-right")
  })

  document.querySelectorAll(".modal-backdrop").forEach((backdrop) => backdrop.remove())
  document.body.classList.remove("modal-open")
  // A normal modal close resets Bootstrap's saved scrollbar styles after the
  // fade completes. Turbo snapshots synchronously, so reset them here instead.
  new ScrollBarHelper().reset()
  document.body.style.removeProperty("overflow")
})
