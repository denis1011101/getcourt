import { Controller } from "@hotwired/stimulus"

// Конструктор тренировки: отмеченные блоки держим сверху в порядке занятия —
// именно этот порядок форма и отправляет. Новые блоки дозаписываются здесь же
// и попадают в библиотеку вместе с сохранением игры.
export default class extends Controller {
  static targets = ["container", "template", "library", "row", "checkbox", "position", "moveControls", "coachSelect"]
  static values = { nextIndex: Number, libraryUrl: String, gameId: String }

  connect() {
    this.renumber()
  }

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

  reorder(event) {
    const row = event.target.closest("[data-training-plan-block-row]")
    if (row) this.moveToPlanEdge(row, event.target.checked)
    this.renumber()
  }

  moveUp(event) {
    event.preventDefault()
    this.swap(event.target.closest("[data-training-plan-block-row]"), -1)
  }

  moveDown(event) {
    event.preventDefault()
    this.swap(event.target.closest("[data-training-plan-block-row]"), 1)
  }

  async reloadLibrary() {
    if (!this.hasLibraryTarget || !this.libraryUrlValue) return

    const params = new URLSearchParams()
    if (this.gameIdValue) params.append("game_id", this.gameIdValue)
    this.coachSelectTargets.forEach((select) => { if (select.value) params.append("coach_ids[]", select.value) })
    this.checkedRows().forEach((row) => params.append("training_block_ids[]", this.checkboxIn(row).value))

    const response = await fetch(`${this.libraryUrlValue}?${params}`, {
      headers: { Accept: "text/html" },
      credentials: "same-origin"
    })
    if (!response.ok) return

    this.libraryTarget.innerHTML = await response.text()
    this.renumber()
  }

  // Отмеченный блок встаёт в конец плана, снятый — сразу под ним.
  moveToPlanEdge(row, checked) {
    const chosen = this.checkedRows().filter((candidate) => candidate !== row)
    const last = chosen[chosen.length - 1]

    if (checked && last) {
      last.after(row)
    } else if (checked) {
      row.parentNode.prepend(row)
    } else if (last) {
      last.after(row)
    }
  }

  swap(row, direction) {
    if (!row) return

    const chosen = this.checkedRows()
    const index = chosen.indexOf(row)
    const neighbour = chosen[index + direction]
    if (index < 0 || !neighbour) return

    if (direction < 0) {
      neighbour.before(row)
    } else {
      neighbour.after(row)
    }

    this.renumber()
  }

  renumber() {
    const chosen = this.checkedRows()

    this.rowTargets.forEach((row) => {
      const position = row.querySelector("[data-training-plan-target='position']")
      const controls = row.querySelector("[data-training-plan-target='moveControls']")
      const index = chosen.indexOf(row)

      if (position) position.textContent = index < 0 ? "" : `${index + 1}.`
      if (controls) controls.classList.toggle("invisible", index < 0)
    })
  }

  checkedRows() {
    return this.rowTargets.filter((row) => this.checkboxIn(row)?.checked)
  }

  checkboxIn(row) {
    return row.querySelector("input[type=checkbox]")
  }
}
