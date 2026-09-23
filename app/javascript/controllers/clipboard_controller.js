import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "status"]
  static values = { text: String }

  initialize() {
    this.resetFeedback = this.resetFeedback.bind(this)
  }

  connect() {
    document.addEventListener("turbo:before-cache", this.resetFeedback)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.resetFeedback)
    this.resetFeedback()
  }

  async copy() {
    let copied = false

    try {
      await navigator.clipboard.writeText(this.textValue)
      copied = true
    } catch (_error) {
      copied = this.copyWithLegacyApi()
    }

    const message = copied ? "Copied" : "Copy failed"
    this.buttonTarget.textContent = message
    this.statusTarget.textContent = copied ? "Public event link copied" : "Could not copy the public event link"

    window.clearTimeout(this.resetTimer)
    this.resetTimer = window.setTimeout(() => {
      this.resetFeedback()
    }, 2000)
  }

  resetFeedback() {
    window.clearTimeout(this.resetTimer)
    this.buttonTarget.textContent = "Copy"
    this.statusTarget.textContent = ""
  }

  copyWithLegacyApi() {
    const input = document.createElement("textarea")
    input.value = this.textValue
    input.setAttribute("readonly", "")
    input.style.position = "fixed"
    input.style.opacity = "0"
    document.body.appendChild(input)
    input.select()

    try {
      return document.execCommand("copy")
    } catch (_error) {
      return false
    } finally {
      input.remove()
    }
  }
}
