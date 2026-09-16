import Modal from "bootstrap/js/dist/modal"

document.addEventListener("turbo:before-cache", () => {
  document.querySelectorAll(".modal.show").forEach((modal) => {
    // dispose() removes Bootstrap's listeners and instance data, but it does
    // not hide an open modal. Clean up its visible state before Turbo snapshots it.
    Modal.getInstance(modal)?.dispose()
    modal.classList.remove("show")
    modal.style.display = "none"
    modal.setAttribute("aria-hidden", "true")
  })

  document.querySelectorAll(".modal-backdrop").forEach((backdrop) => backdrop.remove())
  document.body.classList.remove("modal-open")
  document.body.style.removeProperty("padding-right")
})
