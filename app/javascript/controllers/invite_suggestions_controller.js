import { Controller } from "@hotwired/stimulus"

// Fills the invite field with a previously used list of Telegram usernames.
export default class extends Controller {
  static targets = ["input"]

  fill(event) {
    this.inputTarget.value = event.currentTarget.dataset.handles
    this.inputTarget.focus()
  }
}
