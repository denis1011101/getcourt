import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    filename: { type: String, default: "image.png" },
    successLabel: { type: String, default: "Downloaded!" }
  }

  async download(event) {
    event.preventDefault()
    const button = event.currentTarget
    if (!this.urlValue) return

    const original = button.textContent
    button.disabled = true

    try {
      const response = await fetch(this.urlValue, { credentials: "same-origin" })
      if (!response.ok) throw new Error("Network error")
      const blob = await response.blob()
      const objectUrl = URL.createObjectURL(blob)

      const a = document.createElement("a")
      a.href = objectUrl
      a.download = this.filenameValue
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(objectUrl)

      button.textContent = this.successLabelValue
    } catch (_e) {
      window.open(this.urlValue, "_blank", "noopener")
    } finally {
      setTimeout(() => {
        button.textContent = original
        button.disabled = false
      }, 1500)
    }
  }
}
