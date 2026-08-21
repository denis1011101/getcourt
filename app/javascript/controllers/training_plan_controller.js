import { Controller } from "@hotwired/stimulus"

// Конструктор тренировки: блоки из библиотеки отмечаются галочками, а новые
// дозаписываются прямо здесь и попадают в библиотеку вместе с сохранением игры.
export default class extends Controller {
  static targets = ["container", "template"]
  static values = { nextIndex: Number }

  add(event) {
    event.preventDefault()
    const html = this.templateTarget.innerHTML.replaceAll("__INDEX__", this.nextIndexValue)
    this.containerTarget.insertAdjacentHTML("beforeend", html)
    this.nextIndexValue++
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-training-plan-row]")
    if (row) row.remove()
  }
}
