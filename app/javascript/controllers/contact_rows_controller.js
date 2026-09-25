import { Controller } from "@hotwired/stimulus"

// Контактов у корта бывает один-два, поэтому лишние строки прячем за плюсиком.
// Номера в подписях ставит контроллер: после удаления строки они должны идти
// подряд, а не «1, 3».
export default class extends Controller {
  static targets = ["row", "remove", "typeLabel", "valueLabel", "template", "add", "list"]
  static values = { max: Number, typeLabel: String, valueLabel: String }

  connect() {
    this.renumber()
  }

  add() {
    if (this.rowTargets.length >= this.maxValue) return

    this.listTarget.appendChild(this.templateTarget.content.cloneNode(true))
    this.renumber()
    this.rowTargets[this.rowTargets.length - 1].querySelector("select")?.focus()
  }

  remove(event) {
    // Последнюю строку не убираем: пустая форма контактов выглядит поломанной.
    if (this.rowTargets.length <= 1) return

    event.target.closest("[data-contact-rows-target='row']").remove()
    this.renumber()
  }

  renumber() {
    const rows = this.rowTargets
    rows.forEach((row, index) => {
      const number = index + 1
      row.querySelector("[data-contact-rows-target='typeLabel']").textContent = this.typeLabelValue.replace("%{number}", number)
      row.querySelector("[data-contact-rows-target='valueLabel']").textContent = this.valueLabelValue.replace("%{number}", number)
      row.querySelector("[data-contact-rows-target='remove']").hidden = rows.length <= 1
    })
    if (this.hasAddTarget) this.addTarget.hidden = rows.length >= this.maxValue
  }
}
