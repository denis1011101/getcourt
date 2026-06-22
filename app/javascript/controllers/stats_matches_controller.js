import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "template"]
  static values = { nextIndex: Number }

  add(event) {
    event.preventDefault()
    const nextNumber = this.nextIndexValue + 1
    const html = this.templateTarget.innerHTML
      .replaceAll("__INDEX__", this.nextIndexValue)
      .replaceAll("__NUMBER__", nextNumber)
    this.containerTarget.insertAdjacentHTML("beforeend", html)
    this.nextIndexValue++
  }

  remove(event) {
    event.preventDefault()
    const block = event.target.closest("[data-stats-match-block]")
    if (block) block.remove()
  }
}
