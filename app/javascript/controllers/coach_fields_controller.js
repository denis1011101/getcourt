import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "fields", "select"]

  connect() {
    this.toggle()
  }

  toggle() {
    const enabled = this.checkboxTarget.checked
    this.fieldsTarget.classList.toggle("hidden", !enabled)
    this.selectTarget.disabled = !enabled
  }
}
