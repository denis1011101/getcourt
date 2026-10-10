import { Controller } from "@hotwired/stimulus"

// Подставляет недавнего тренера в выпадающий список — как будто выбрали руками.
export default class extends Controller {
  pick({ params: { select, value } }) {
    const field = document.getElementById(select)
    if (!field) return

    field.value = String(value)
    field.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
