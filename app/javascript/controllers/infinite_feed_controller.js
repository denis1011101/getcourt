import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["sentinel", "link", "error"]
  static values = { autoLimit: { type: Number, default: 10 } }

  connect() {
    this.loading = false
    this.autoLoads = 0
    this.observer = new IntersectionObserver(
      entries => {
        if (entries.some(entry => entry.isIntersecting)) this.load()
      },
      { rootMargin: "600px" }
    )
  }

  disconnect() {
    this.observer?.disconnect()
  }

  sentinelTargetConnected(element) {
    requestAnimationFrame(() => this.observeSentinel(element))
  }

  sentinelTargetDisconnected(element) {
    this.observer?.unobserve(element)
  }

  async load(event) {
    event?.preventDefault()
    if (this.loading || !this.hasLinkTarget) return

    this.loading = true
    this.observer?.unobserve(this.sentinelTarget)
    this.linkTarget.setAttribute("aria-busy", "true")
    if (this.hasErrorTarget) this.errorTarget.classList.add("hidden")

    try {
      const response = await fetch(this.linkTarget.href, {
        headers: { Accept: "text/vnd.turbo-stream.html" },
        credentials: "same-origin"
      })
      const stream = await response.text()
      if (response.status === 410) {
        this.loading = false
        Turbo.renderStreamMessage(stream)
        return
      }
      if (!response.ok) throw new Error(`Feed request failed: ${response.status}`)

      this.autoLoads += 1
      this.loading = false
      Turbo.renderStreamMessage(stream)
    } catch (_error) {
      this.loading = false
      this.linkTarget.removeAttribute("aria-busy")
      this.linkTarget.classList.remove("hidden")
      if (this.hasErrorTarget) this.errorTarget.classList.remove("hidden")
    }
  }

  observeSentinel(element) {
    if (!this.hasLinkTarget) {
      this.observer?.disconnect()
      return
    }

    this.linkTarget.removeAttribute("aria-busy")
    if (this.autoLoads >= this.autoLimitValue) {
      this.linkTarget.classList.remove("hidden")
      this.observer?.disconnect()
    } else {
      this.linkTarget.classList.add("hidden")
      this.observer?.observe(element)
    }
  }
}
