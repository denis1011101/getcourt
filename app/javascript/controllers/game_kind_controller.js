import { Controller } from "@hotwired/stimulus"

// Игра или тренировка: тренеры бывают только у тренировки, поэтому их поля
// живут под переключателем и уезжают вместе с ним.
export default class extends Controller {
  static targets = ["kindRadio", "trainingFields", "withCoach", "coachFields", "coachSelect"]

  connect() {
    this.toggle()
  }

  toggle() {
    const training = this.kindRadioTargets.some((radio) => radio.checked && radio.value === "training")
    this.trainingFieldsTarget.classList.toggle("hidden", !training)
    if (!training) this.withCoachTarget.checked = false

    this.toggleCoaches()
  }

  toggleCoaches() {
    const enabled = this.withCoachTarget.checked
    this.coachFieldsTarget.classList.toggle("hidden", !enabled)
    this.coachSelectTargets.forEach((select) => { select.disabled = !enabled })
  }
}
