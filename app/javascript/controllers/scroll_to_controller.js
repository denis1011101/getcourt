import { Controller } from "@hotwired/stimulus"

// Клик по дню в календаре предзаписи ведёт к карточке этого дня. Обычный якорь
// ставит её под самую шапку; здесь она плавно встаёт по центру экрана и
// подсвечивается — так видно, куда именно приехали, даже на широком экране,
// где все карточки и так на виду. Без JS остаётся сам якорь.
export default class extends Controller {
  static classes = ["highlight"]

  center(event) {
    const id = event.currentTarget.getAttribute("href").slice(1)
    const card = document.getElementById(id)
    if (!card) return

    event.preventDefault()
    document.querySelectorAll("[data-testid='prebooking-day']").forEach((other) => other.classList.remove(...this.highlightClasses))
    card.classList.add(...this.highlightClasses)
    card.scrollIntoView({ block: "center", behavior: "smooth" })
    history.replaceState(history.state, "", `#${id}`)
  }
}
