import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
    } catch (_error) {
      const input = document.createElement("textarea")
      input.value = this.textValue
      input.setAttribute("readonly", "")
      input.style.position = "fixed"
      input.style.opacity = "0"
      document.body.appendChild(input)
      input.select()
      document.execCommand("copy")
      input.remove()
    }

    this.element.textContent = "Copied"
  }
}
