import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "list"]
  static values = { fieldName: String }

  add(event) {
    event.preventDefault()
    const option = this.selectTarget.selectedOptions[0]
    if (!option || !option.value) return
    if (this.listTarget.querySelector(`input[value="${CSS.escape(option.value)}"]`)) return

    const label = document.createElement("label")
    label.className = "flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300"

    const checkbox = document.createElement("input")
    checkbox.type = "checkbox"
    checkbox.name = this.fieldNameValue
    checkbox.value = option.value
    checkbox.checked = true
    checkbox.className = "rounded border-gray-300 dark:border-white/15 dark:bg-slate-700 dark:text-slate-100"

    const span = document.createElement("span")
    span.textContent = option.textContent

    label.append(checkbox, span)
    this.listTarget.appendChild(label)
    this.selectTarget.value = ""
  }
}