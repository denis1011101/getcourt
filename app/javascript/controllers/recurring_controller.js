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
    if (prebooking) prebooking.disabled = !enabled
    // keep hidden field in sync if you still use it elsewhere
    const hidden = document.getElementById('prebooking_recurring_hidden')
    if (hidden) hidden.value = enabled ? '1' : '0'
  }
}
