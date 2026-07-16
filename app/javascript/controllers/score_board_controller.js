import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "score", "sets", "set", "template", "addButton", "topLabel", "bottomLabel",
    "preview", "photo", "recognizeButton", "recognizeLabel", "status"
  ]

  static values = {
    recognitionUrl: String,
    setLabel: String,
    teamALabel: String,
    teamBLabel: String,
    recognizingLabel: String,
    recognitionFailedLabel: String,
    invalidSetLabel: String,
    namesHintTemplate: String
  }

  connect() {
    this.matchBlock = this.element.closest("[data-stats-match-block]")
    this.winnerManuallySelected = this.winnerInputs().some((input) => input.checked)
    this.idleRecognizeLabel = this.recognizeLabelTarget.textContent
    this.refreshLabels = this.refreshLabels.bind(this)
    this.trackWinnerSelection = this.trackWinnerSelection.bind(this)
    this.matchBlock?.addEventListener("input", this.refreshLabels)
    this.matchBlock?.addEventListener("change", this.refreshLabels)
    this.matchBlock?.addEventListener("change", this.trackWinnerSelection)
    this.playerListObservers = Array.from(
      this.matchBlock?.querySelectorAll("[data-team-players-target~='list']") || []
    ).map((list) => {
      const observer = new MutationObserver(this.refreshLabels)
      observer.observe(list, { childList: true })
      return observer
    })
    const initialScore = this.scoreTarget.value.trim()
    const initialSets = this.parseScore(initialScore)
    if (this.setTargets.length === 0) {
      if (initialSets?.length) {
        initialSets.forEach((set) => this.appendSet(set))
      } else {
        for (let index = 0; index < 3; index++) this.appendSet()
      }
    }
    this.refreshLabels()
    if (initialSets === null) {
      this.previewTarget.textContent = initialScore
    } else {
      this.serialize()
    }
  }

  disconnect() {
    this.matchBlock?.removeEventListener("input", this.refreshLabels)
    this.matchBlock?.removeEventListener("change", this.refreshLabels)
    this.matchBlock?.removeEventListener("change", this.trackWinnerSelection)
    this.playerListObservers.forEach((observer) => observer.disconnect())
  }

  addSet(event) {
    event?.preventDefault()
    if (this.setTargets.length >= 5) return

    this.appendSet()
    this.serialize()
  }

  removeSet(event) {
    event.preventDefault()
    if (this.setTargets.length <= 1) return

    event.currentTarget.closest("[data-score-board-target~='set']")?.remove()
    this.renumberSets()
    this.serialize()
  }

  scoreChanged() {
    this.serialize()
  }

  swap(event) {
    event.preventDefault()
    this.setTargets.forEach((set) => {
      this.swapValues(set.querySelector("[data-role='top']"), set.querySelector("[data-role='bottom']"))
      this.swapValues(set.querySelector("[data-role='tiebreak-top']"), set.querySelector("[data-role='tiebreak-bottom']"))
    })
    this.serialize()
  }

  choosePhoto(event) {
    event.preventDefault()
    this.photoTarget.click()
  }

  async recognize() {
    const file = this.photoTarget.files[0]
    if (!file) return

    this.setBusy(true)
    this.showStatus("")

    try {
      const body = new FormData()
      body.append("photo", file)
      const response = await fetch(this.recognitionUrlValue, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body
      })
      const payload = await response.json()
      if (!response.ok) throw new Error(payload.error || this.recognitionFailedLabelValue)
      if (!Array.isArray(payload.sets) || payload.sets.length === 0) {
        throw new Error(this.recognitionFailedLabelValue)
      }

      this.fillScore(payload.sets.slice(0, 5))
      this.showRecognizedNames(payload.top_names, payload.bottom_names)
    } catch (error) {
      this.showStatus(error.message || this.recognitionFailedLabelValue, true)
    } finally {
      this.photoTarget.value = ""
      this.setBusy(false)
    }
  }

  appendSet(values = {}) {
    const set = this.templateTarget.content.firstElementChild.cloneNode(true)
    set.querySelector("[data-role='top']").value = values.top ?? ""
    set.querySelector("[data-role='bottom']").value = values.bottom ?? ""
    set.querySelector("[data-role='tiebreak-top']").value = values.tiebreak_top ?? ""
    set.querySelector("[data-role='tiebreak-bottom']").value = values.tiebreak_bottom ?? ""
    this.setsTarget.appendChild(set)
    this.renumberSets()
    return set
  }

  fillScore(sets) {
    this.setsTarget.replaceChildren()
    sets.forEach((set) => this.appendSet(set))
    this.serialize()
  }

  serialize() {
    const scores = []
    let topSets = 0
    let bottomSets = 0

    this.setTargets.forEach((set) => {
      const top = this.numberValue(set, "top")
      const bottom = this.numberValue(set, "bottom")
      this.updateTiebreaks(set, top, bottom)
      this.validateSet(set, top, bottom)
      if (top === null || bottom === null) return

      let score = `${top}-${bottom}`
      const tiebreak = top === 6 && bottom === 7
        ? this.numberValue(set, "tiebreak-top")
        : top === 7 && bottom === 6
          ? this.numberValue(set, "tiebreak-bottom")
          : null
      if (tiebreak !== null) score += `(${tiebreak})`
      scores.push(score)

      if (top > bottom) topSets++
      if (bottom > top) bottomSets++
    })

    this.scoreTarget.value = scores.join(" ")
    this.previewTarget.textContent = this.scoreTarget.value || "—"
    this.updateWinner(topSets, bottomSets, scores.length)
  }

  updateTiebreaks(set, top, bottom) {
    const topTiebreak = set.querySelector("[data-role='tiebreak-top']")
    const bottomTiebreak = set.querySelector("[data-role='tiebreak-bottom']")
    topTiebreak.classList.toggle("hidden", !(top === 6 && bottom === 7))
    bottomTiebreak.classList.toggle("hidden", !(top === 7 && bottom === 6))
  }

  validateSet(set, top, bottom) {
    const invalid = top !== null && bottom !== null && !this.plausibleSet(top, bottom)
    set.classList.toggle("border-amber-400", invalid)
    set.classList.toggle("bg-amber-50", invalid)
    set.classList.toggle("dark:bg-amber-950/20", invalid)
    set.title = invalid ? this.invalidSetLabelValue : ""
  }

  plausibleSet(top, bottom) {
    if (top === bottom) return false
    const winner = Math.max(top, bottom)
    const loser = Math.min(top, bottom)
    if (winner === 6 && loser <= 4) return true
    if (winner === 7 && [5, 6].includes(loser)) return true
    if (winner === 10 && loser <= 8) return true
    return winner >= 8 && loser >= 6 && winner - loser === 2
  }

  updateWinner(topSets, bottomSets, completedSets) {
    if (!this.matchBlock || completedSets === 0 || this.winnerManuallySelected) return
    const winner = topSets > bottomSets ? "a" : bottomSets > topSets ? "b" : "draw"
    const radio = this.winnerInputs().find((input) => input.value === winner)
    if (radio) radio.checked = true
  }

  trackWinnerSelection(event) {
    if (event.target.matches("input[type='radio'][name$='[winner_team]']")) {
      this.winnerManuallySelected = true
    }
  }

  winnerInputs() {
    return Array.from(this.matchBlock?.querySelectorAll("input[type='radio'][name$='[winner_team]']") || [])
  }

  parseScore(score) {
    if (!score) return []

    const sets = score.split(/\s+/).map((value) => {
      const match = value.match(/^(\d{1,2})-(\d{1,2})(?:\((\d{1,2})\))?$/)
      if (!match) return null

      const set = { top: Number(match[1]), bottom: Number(match[2]) }
      if (match[3] && set.top === 6 && set.bottom === 7) {
        set.tiebreak_top = Number(match[3])
      } else if (match[3] && set.top === 7 && set.bottom === 6) {
        set.tiebreak_bottom = Number(match[3])
      } else if (match[3]) {
        return null
      }
      return set
    })

    return sets.length <= 5 && sets.every(Boolean) ? sets : null
  }

  refreshLabels() {
    if (!this.matchBlock) return
    const topLabel = this.teamNames("a") || this.teamALabelValue
    const bottomLabel = this.teamNames("b") || this.teamBLabelValue
    if (this.topLabelTarget.textContent !== topLabel) this.topLabelTarget.textContent = topLabel
    if (this.bottomLabelTarget.textContent !== bottomLabel) this.bottomLabelTarget.textContent = bottomLabel
  }

  teamNames(team) {
    const names = Array.from(this.matchBlock.querySelectorAll("input[type='checkbox']"))
      .filter((input) => input.checked && input.name.includes(`[team_${team}_`))
      .map((input) => input.closest("label")?.querySelector("span")?.textContent?.trim())
      .filter(Boolean)
    const guests = this.matchBlock.querySelector(`input[name$='[team_${team}_guests]']`)?.value
      .split(",").map((name) => name.trim()).filter(Boolean) || []
    return [...new Set([...names, ...guests])].join(", ")
  }

  showRecognizedNames(topNames = [], bottomNames = []) {
    if (topNames.length === 0 && bottomNames.length === 0) {
      this.showStatus("")
      return
    }
    const top = this.matchNames(topNames).join(", ") || "—"
    const bottom = this.matchNames(bottomNames).join(", ") || "—"
    const message = this.namesHintTemplateValue.replace("__TOP__", top).replace("__BOTTOM__", bottom)
    this.showStatus(message)
  }

  matchNames(names) {
    const labels = Array.from(this.matchBlock?.querySelectorAll("input[type='checkbox']") || [])
      .filter((input) => input.name.includes("[team_"))
      .map((input) => input.closest("label")?.querySelector("span")?.textContent?.trim())
      .filter(Boolean)
    return Array.from(new Set(names.map((name) => {
      const normalized = this.normalizeName(name)
      return labels.find((label) => {
        const candidate = this.normalizeName(label)
        return candidate.includes(normalized) || normalized.includes(candidate)
      }) || name
    })))
  }

  normalizeName(name) {
    return String(name).toLocaleLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim()
  }

  renumberSets() {
    this.setTargets.forEach((set, index) => {
      set.querySelector("[data-role='set-label']").textContent = `${this.setLabelValue} ${index + 1}`
      set.querySelector("[data-role='remove-set']").classList.toggle("invisible", this.setTargets.length === 1)
    })
    this.addButtonTarget.classList.toggle("hidden", this.setTargets.length >= 5)
  }

  numberValue(set, role) {
    const value = set.querySelector(`[data-role='${role}']`).value.trim()
    return /^\d{1,2}$/.test(value) ? Number.parseInt(value, 10) : null
  }

  swapValues(first, second) {
    const value = first.value
    first.value = second.value
    second.value = value
  }

  setBusy(busy) {
    this.recognizeButtonTarget.disabled = busy
    this.recognizeLabelTarget.textContent = busy ? this.recognizingLabelValue : this.idleRecognizeLabel
  }

  showStatus(message, error = false) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("hidden", !message)
    this.statusTarget.classList.toggle("text-red-600", error)
    this.statusTarget.classList.toggle("dark:text-red-400", error)
  }
}
