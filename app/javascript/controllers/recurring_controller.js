import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // ensure initial state on page load
    this.updatePrebooking(this.element.checked)
  }

  toggle(event) {
    this.updatePrebooking(event.target.checked)
  }

  updatePrebooking(enabled) {
    const prebooking = document.getElementById('game_prebooking_enabled')
    if (!prebooking) return

    prebooking.disabled = !enabled
    if (!enabled) prebooking.checked = false
  }
}
