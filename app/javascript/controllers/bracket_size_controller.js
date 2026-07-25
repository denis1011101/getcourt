import { Controller } from "@hotwired/stimulus"

// Warns while filling in the tournament form that the player count does not fill a
// bracket: the missing slots become byes, and those players advance without playing.
export default class extends Controller {
  static targets = ["playersCount", "type", "message"]
  static values = { template: String }

  connect() {
    this.refresh()
  }

  refresh() {
    const message = this.warning()
    this.messageTarget.textContent = message || ""
    this.messageTarget.classList.toggle("hidden", !message)
  }

  warning() {
    if (!this.bracketSelected()) return null

    const players = Number.parseInt(this.playersCountTarget.value, 10)
    if (!Number.isInteger(players) || players < 2) return null

    let size = 1
    while (size < players) size *= 2
    const byes = size - players
    if (byes === 0) return null

    return this.templateValue
      .replace("__PLAYERS__", players)
      .replace("__BYES__", byes)
      .replace("__MISSING__", byes)
      .replace("__SIZE__", size)
  }

  bracketSelected() {
    const checked = this.typeTargets.find((input) => input.checked)
    return !checked || checked.value === "bracket"
  }
}
