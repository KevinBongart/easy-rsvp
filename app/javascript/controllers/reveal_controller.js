import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "trigger"]

  show(event) {
    event.preventDefault()
    this.contentTarget.classList.remove("d-none")
    this.triggerTarget.hidden = true
  }
}
