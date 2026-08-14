import { Controller } from "@hotwired/stimulus"

// Fills the invite field with a previously used list of Telegram usernames.
export default class extends Controller {
  static targets = ["input"]

  fill(event) {
    const handles = [this.inputTarget.value, event.currentTarget.dataset.handles]
      .flatMap((value) => value.split(/[\s,]+/))
      .filter(Boolean)
    const uniqueHandles = handles.filter((handle, index) =>
      handles.findIndex((candidate) => this.normalize(candidate) === this.normalize(handle)) === index
    )

    this.inputTarget.value = uniqueHandles.join(", ")
    this.inputTarget.focus()
  }

  normalize(handle) {
    return handle.replace(/^@/, "").toLowerCase()
  }
}
