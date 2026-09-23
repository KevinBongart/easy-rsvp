import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "fields", "input", "timeZone"]

  connect() {
    this.update()
  }

  toggle() {
    this.update()
  }

  update() {
    const enabled = this.toggleTarget.checked

    this.fieldsTarget.hidden = !enabled
    this.inputTargets.forEach((input) => {
      input.disabled = !enabled
      input.required = enabled
    })

    if (enabled && !this.timeZoneTarget.value) {
      const detectedTimeZone = Intl.DateTimeFormat().resolvedOptions().timeZone
      if (detectedTimeZone) this.timeZoneTarget.value = detectedTimeZone
    }
  }
}
