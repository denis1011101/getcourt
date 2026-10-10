import { Controller } from "@hotwired/stimulus"

// Галка «С тренером» есть только у тренировки, а выбор тренеров — только при
// галке, как в форме игры: выбрали игру — галку прячем и снимаем.
export default class extends Controller {
  static targets = ["coach", "coachFields"]

  toggleCoach(event) {
    const training = event.target.value === "training"
    this.coachTarget.hidden = !training
    if (!training) {
      this.coachTarget.querySelector("input[type=checkbox]").checked = false
      this.coachFieldsTarget.hidden = true
    }
  }

  toggleCoachFields(event) {
    this.coachFieldsTarget.hidden = !event.target.checked
  }
}
