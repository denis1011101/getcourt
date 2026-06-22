import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    text: String,
    successLabel: { type: String, default: "Copied!" }
  }

  async copy(event) {
    event.preventDefault()
    const button = event.currentTarget
    const text = this.textValue
    if (!text) return

    try {
      await navigator.clipboard.writeText(text)
    } catch (_e) {
      const ta = document.createElement("textarea")
      ta.value = text
      ta.setAttribute("readonly", "")
      ta.style.position = "absolute"
      ta.style.left = "-9999px"
      document.body.appendChild(ta)
      ta.select()
      try { document.execCommand("copy") } catch (_) {}
      document.body.removeChild(ta)
    }

    const original = button.textContent
    button.textContent = this.successLabelValue
    button.disabled = true
    setTimeout(() => {
      button.textContent = original
      button.disabled = false
    }, 1500)
  }
}
