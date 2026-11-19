import { Controller } from "@hotwired/stimulus"
import Trix from "trix"

const acceptedImageTypes = ["image/png", "image/jpeg", "image/gif", "image/webp"]
// Keep in step with RichTextDirectUploadsController::MAXIMUM_SIZE and
// Event::MAXIMUM_IMAGES_SIZE; the server enforces both.
const maximumImageSize = 5 * 1024 * 1024
const maximumImagesSize = 10 * 1024 * 1024
const uploadErrorMessage = "Image upload failed. Please try again with a PNG, JPEG, GIF, or WebP image (5 MB maximum)."
const imagesTooLargeMessage = "Images in the description can add up to 10 MB; remove some and try again."

export default class extends Controller {
  connect() {
    Trix.config.attachments.preview.caption = { name: false, size: false }
  }

  acceptFile(event) {
    const { file } = event

    if (!acceptedImageTypes.includes(file.type) || file.size === 0 || file.size > maximumImageSize) {
      event.preventDefault()
      this.showUploadError(uploadErrorMessage)
    } else if (this.attachedImagesSize + this.pendingImagesSize + file.size > maximumImagesSize) {
      event.preventDefault()
      this.showUploadError(imagesTooLargeMessage)
    } else {
      this.trackPendingImage(file.size)
    }
  }

  // Trix asks about every file of a multi-file drop or pick before inserting
  // any of them, so files accepted earlier in the same batch are not in the
  // document yet. Count them until the batch has been inserted.
  trackPendingImage(size) {
    this.pendingImagesSize = this.pendingImagesSize + size
    if (this.pendingReset) return

    this.pendingReset = true
    queueMicrotask(() => {
      this.pendingImagesSize = 0
      this.pendingReset = false
    })
  }

  get pendingImagesSize() {
    return this._pendingImagesSize || 0
  }

  set pendingImagesSize(size) {
    this._pendingImagesSize = size
  }

  uploadFailed(event) {
    event.preventDefault()
    event.detail.attachment.remove()
    this.showUploadError(uploadErrorMessage)
  }

  uploadFinished() {
    this.errorElement?.remove()
  }

  showUploadError(message) {
    this.errorElement?.remove()

    const error = document.createElement("div")
    error.className = "alert alert-danger trix-upload-error"
    error.setAttribute("role", "alert")
    error.textContent = message
    this.element.insertAdjacentElement("afterend", error)
  }

  // Images already in the editor, including uploads in progress. An image
  // embedded twice is stored once, so it counts once.
  get attachedImagesSize() {
    const sizes = new Map()
    for (const attachment of this.element.editor.getDocument().getAttachments()) {
      const key = attachment.getAttribute("sgid") || attachment.getAttribute("url") || attachment.id
      sizes.set(key, Number(attachment.getFilesize()) || 0)
    }
    return [...sizes.values()].reduce((total, size) => total + size, 0)
  }

  get errorElement() {
    return this.element.parentNode.querySelector(".trix-upload-error")
  }
}
