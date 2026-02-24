import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["question", "result", "resultLevel", "resultDescription", "startBtn", "quizSection"]
  static values = { current: { type: Number, default: 0 }, scores: { type: Array, default: [] } }

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

    const descriptions = {
      2.5: "You are a beginner — you can rally at a moderate pace, but consistency drops under pressure.",
      3.0: "You are developing — rallies are more sustained and you're starting to use basic tactics.",
      3.5: "Intermediate level — more reliable strokes, basic tactics, and better court positioning.",
      4.0: "Advanced intermediate — consistent serves and groundstrokes, directional control, and point construction.",
      4.5: "Advanced — strong all-court game, pace control, advanced patterns, and high match consistency.",
      5.0: "Strong advanced — powerful, reliable strokes with tactical flexibility.",
      5.5: "Tournament-level — exceptional consistency, shot variety, and match management under pressure.",
      6.0: "Elite-level competitor with national/international training and results."
    }

    const clamped = Math.max(2.5, Math.min(6.0, level))
    this.resultLevelTarget.textContent = clamped.toFixed(1)
    this.resultDescriptionTarget.textContent = descriptions[clamped] || descriptions[Math.round(clamped * 2) / 2] || descriptions[4.0]

    this.quizSectionTarget.classList.add("hidden")
    this.resultTarget.classList.remove("hidden")
  }

  restart() {
    this.start()
  }
}
