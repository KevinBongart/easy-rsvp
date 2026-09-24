import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["timeZone"]

  connect() {
    if (this.element.open) this.detectTimeZone()
  }

  detectTimeZone() {
    if (!this.element.open || this.timeZoneTarget.value) return

    const detectedTimeZone = Intl.DateTimeFormat().resolvedOptions().timeZone
    if (detectedTimeZone) this.timeZoneTarget.value = detectedTimeZone
  }

  normalizeTime(event) {
    const match = event.target.value.trim().match(/^(\d{1,2})(?::(\d{1,2}))?\s*([ap](?:\.?m\.?)?)?$/i)
    if (!match) return

    const hourText = match[1]
    let hour = Number(hourText)
    const minute = Number(match[2] || 0)
    const meridiem = match[3]?.replaceAll(".", "").toLowerCase()
    if (minute > 59 || (meridiem && (hour < 1 || hour > 12)) || (!meridiem && hour > 23)) return

    if (meridiem?.startsWith("a")) hour %= 12
    else if (meridiem?.startsWith("p") || (hour >= 1 && hour <= 12 && !hourText.startsWith("0"))) hour = (hour % 12) + 12

    const displayHour = hour % 12 || 12
    const displayMinute = String(minute).padStart(2, "0")
    const displayMeridiem = hour < 12 ? "AM" : "PM"
    event.target.value = `${displayHour}:${displayMinute} ${displayMeridiem}`
  }
}
