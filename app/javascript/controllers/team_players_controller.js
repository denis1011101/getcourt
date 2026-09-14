import { Controller } from "@hotwired/stimulus"

// Список добавленных в команду игроков под полем выбора (shared/user_picker):
// выбор прилетает событием user-picker:selected и становится отмеченной галкой
// с тем же именем поля, что у галок состава.
export default class extends Controller {
  static targets = ["list"]
  static values = { fieldName: String }

  add(event) {
    const { id, label } = event.detail
    if (!id) return

    // Тот, кто уже стоит в составе или добавлен раньше, второй галки не
    // получает — его просто отмечаем.
    const existing = this.element
      .closest("[data-stats-match-block]")
      ?.querySelector(`input[name="${CSS.escape(this.fieldNameValue)}"][value="${CSS.escape(id)}"]`)
    if (existing) {
      existing.checked = true
      return
    }

    const checkboxLabel = document.createElement("label")
    checkboxLabel.className = "flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300"

    const checkbox = document.createElement("input")
    checkbox.type = "checkbox"
    checkbox.name = this.fieldNameValue
    checkbox.value = id
    checkbox.checked = true
    checkbox.className = "rounded border-gray-300 dark:border-white/15 dark:bg-slate-700 dark:text-slate-100"

    const span = document.createElement("span")
    span.textContent = label

    checkboxLabel.append(checkbox, span)
    this.listTarget.appendChild(checkboxLabel)
  }
}
