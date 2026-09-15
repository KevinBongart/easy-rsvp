import { Controller } from "@hotwired/stimulus"
import Trix from "trix"

const acceptedImageTypes = ["image/png", "image/jpeg", "image/gif", "image/webp"]
const maximumImageSize = 10 * 1024 * 1024

export default class extends Controller {
  connect() {
    Trix.config.attachments.preview.caption = { name: false, size: false }
  }

  acceptFile(event) {
    const { file } = event

    if (!acceptedImageTypes.includes(file.type) || file.size === 0 || file.size > maximumImageSize) {
      event.preventDefault()
      this.showUploadError()
    }
  }

  uploadFailed(event) {
    event.preventDefault()
    event.detail.attachment.remove()
    this.showUploadError()
  }

  uploadFinished() {
    this.errorElement?.remove()
  }

  showUploadError() {
    this.errorElement?.remove()

    const error = document.createElement("div")
    error.className = "alert alert-danger trix-upload-error"
    error.setAttribute("role", "alert")
    error.textContent = "Image upload failed. Please try again with a PNG, JPEG, GIF, or WebP image (10 MB maximum)."
    this.element.insertAdjacentElement("afterend", error)
  }

  get errorElement() {
    return this.element.parentNode.querySelector(".trix-upload-error")
  }
}
