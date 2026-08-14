import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["widget"]
  static values = { post: String }

  connect() {
    this.observer = new IntersectionObserver(
      entries => {
        if (entries.some(entry => entry.isIntersecting)) this.load()
      },
      { rootMargin: "400px" }
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  load() {
    if (this.loaded || !this.hasWidgetTarget || !this.hasPostValue) return

    this.loaded = true
    this.observer?.disconnect()
    this.widgetTarget.classList.remove("hidden")

    const script = document.createElement("script")
    script.async = true
    script.src = "https://telegram.org/js/telegram-widget.js?22"
    script.dataset.telegramPost = this.postValue
    script.dataset.width = "100%"
    script.dataset.userpic = "true"
    if (this.darkTheme) script.dataset.dark = "1"
    script.addEventListener("error", () => this.widgetTarget.classList.add("hidden"))
    this.widgetTarget.append(script)
  }

  get darkTheme() {
    return document.documentElement.classList.contains("dark") ||
      window.matchMedia?.("(prefers-color-scheme: dark)").matches
  }
}
