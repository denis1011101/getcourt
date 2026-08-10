import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["question", "result", "resultLevel", "resultDescription", "startBtn", "quizSection"]
  static values = {
    current: { type: Number, default: 0 },
    scores: { type: Array, default: [] },
    descriptions: Object
  }

  start() {
    this.scoresValue = []
    this.currentValue = 0
    this.startBtnTarget.classList.add("hidden")
    this.quizSectionTarget.classList.remove("hidden")
    this.resultTarget.classList.add("hidden")
    this.showQuestion(0)
  }

  showQuestion(index) {
    this.questionTargets.forEach((q, i) => {
      q.classList.toggle("hidden", i !== index)
    })
  }

  answer(event) {
    const score = parseFloat(event.currentTarget.dataset.score)
    this.scoresValue = [...this.scoresValue, score]
    const next = this.currentValue + 1

    if (next < this.questionTargets.length) {
      this.currentValue = next
      this.showQuestion(next)
    } else {
      this.showResult()
    }
  }

  showResult() {
    const scores = this.scoresValue
    const avg = scores.reduce((a, b) => a + b, 0) / scores.length
    // Round to nearest 0.5
    const level = Math.round(avg * 2) / 2

    const clamped = Math.max(2.5, Math.min(6.0, level))
    this.resultLevelTarget.textContent = clamped.toFixed(1)
    const key = clamped.toFixed(1).replace(".", "_")
    this.resultDescriptionTarget.textContent = this.descriptionsValue[key] || this.descriptionsValue["4_0"]

    this.quizSectionTarget.classList.add("hidden")
    this.resultTarget.classList.remove("hidden")
  }

  restart() {
    this.start()
  }
}
