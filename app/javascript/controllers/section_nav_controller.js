import { Controller } from "@hotwired/stimulus"

// Якоря по разделам страницы игры: подсвечивает раздел, до которого
// долистали, и плавно ведёт к разделу по клику. Активный пункт на телефоне
// подкатывается в видимую часть капсулы.
export default class extends Controller {
  static targets = ["bar", "link"]

  connect() {
    this.onScroll = () => {
      if (this.frame) return
      this.frame = requestAnimationFrame(() => {
        this.frame = null
        this.highlight()
      })
    }
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.highlight()
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
    if (this.frame) cancelAnimationFrame(this.frame)
  }

  go(event) {
    const section = this.sectionFor(event.currentTarget)
    if (!section) return

    event.preventDefault()
    section.scrollIntoView({ behavior: "smooth", block: "start" })
    history.replaceState(null, "", event.currentTarget.hash)
  }

  highlight() {
    // Раздел считается текущим, когда его верх ушёл под капсулу; у самого
    // низа страницы — последний, иначе короткий хвост никогда не загорится.
    const line = this.element.getBoundingClientRect().bottom + 24
    const atBottom = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 4
    let active = this.linkTargets[0]

    this.linkTargets.forEach((link) => {
      const section = this.sectionFor(link)
      if (section && section.getBoundingClientRect().top <= line) active = link
    })
    if (atBottom) active = this.linkTargets[this.linkTargets.length - 1]

    if (active === this.current) return
    this.current = active
    this.linkTargets.forEach((link) => link.setAttribute("aria-current", link === active ? "true" : "false"))
    this.bar.scrollTo({ left: active.offsetLeft - (this.bar.clientWidth - active.offsetWidth) / 2, behavior: "smooth" })
  }

  sectionFor(link) {
    return document.getElementById(link.hash.slice(1))
  }

  get bar() {
    return this.barTarget
  }
}
