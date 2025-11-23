import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button", "results"]

  connect() {
    this.isLocating = false
    this.isSearching = false
    this.searchTimeout = null
    this.clearResultsTimeout = null
    this.lastSearchResults = []

    // Добавляем слушатели один раз
    if (this.hasInputTarget) {
      this.inputTarget.addEventListener("blur", () => this.scheduleResultsClear())
    }
    if (this.hasResultsTarget) {
      this.resultsTarget.addEventListener("pointerdown", () => this.cancelResultsClear())
      this.resultsTarget.addEventListener("touchstart", () => this.cancelResultsClear(), { passive: true })
    }
  }

  disconnect() {
    clearTimeout(this.searchTimeout)
    clearTimeout(this.clearResultsTimeout)
  }

  scheduleResultsClear() {
    this.clearResultsTimeout = setTimeout(() => this.clearResults(), 200)
  }

  cancelResultsClear() {
    clearTimeout(this.clearResultsTimeout)
    this.clearResultsTimeout = null
  }

  locate() {
    if (this.isLocating || !navigator.geolocation) {
      !navigator.geolocation && window.alert("Geolocation is not supported by your browser.")
      return
    }

    this.isLocating = true
    this.updateButton(true)

    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const { latitude, longitude } = pos.coords
        this.setCoordinates(latitude, longitude)
        this.updateButton(false)
        this.dispatch("success", { detail: { lat: latitude, lng: longitude } })
      },
      (err) => {
        this.updateButton(false)
        window.alert(this.getGeolocationErrorMessage(err))
        this.dispatch("error", { detail: { error: err } })
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 }
    )
  }

  getGeolocationErrorMessage(err) {
    const messages = {
      [err.PERMISSION_DENIED]: "Location access denied. Please allow location access in your browser settings.",
      [err.POSITION_UNAVAILABLE]: "Location information is unavailable.",
      [err.TIMEOUT]: "Location request timed out."
    }
    return messages[err.code] || "Failed to get location."
  }

  updateButton(disabled) {
    if (!this.hasButtonTarget) return
    this.buttonTarget.disabled = disabled
    this.buttonTarget.textContent = disabled ? "Locating..." : (this.buttonTarget.dataset.prevText || "Use my location")
    if (!disabled) delete this.buttonTarget.dataset.prevText
    else this.buttonTarget.dataset.prevText = this.buttonTarget.textContent
  }

  setCoordinates(lat, lon) {
    if (this.hasInputTarget) {
      this.inputTarget.value = `${lat.toFixed(6)},${lon.toFixed(6)}`
    }
    this.isLocating = false
  }

  isCoordinates(str) {
    return /^-?\d+\.?\d*\s*,\s*-?\d+\.?\d*$/.test(str.trim())
  }

  onLocationInput(event) {
    clearTimeout(this.searchTimeout)
    const input = event?.target?.value?.trim() || ""

    if (!input || this.isCoordinates(input)) {
      this.clearResults()
      return
    }

    this.searchTimeout = setTimeout(() => this.searchCity(input), 300)
  }

  async searchCity(q) {
    const query = typeof q === "string" ? q.trim() : (this.hasInputTarget ? this.inputTarget.value.trim() : "")

    if (!query || this.isCoordinates(query) || this.isSearching) return

    this.isSearching = true
    this.renderResults([{ label: "Searching...", class: "muted" }])

    try {
      let data = await this.fetchResults(query, "en")
      if (!data?.length) data = await this.fetchResults(query, "ru")

      this.renderResults(
        data?.length
          ? data.map(item => ({
              label: item.display_name,
              lat: parseFloat(item.lat),
              lon: parseFloat(item.lon)
            }))
          : [{ label: "No results found", class: "muted" }]
      )
    } catch (err) {
      console.warn("Geocoding error:", err)
      this.renderResults([{ label: "Error searching. Please try again.", class: "muted" }])
    } finally {
      this.isSearching = false
    }
  }

  async fetchResults(query, lang) {
    const url = `https://nominatim.openstreetmap.org/search?format=json&addressdetails=1&limit=5&q=${encodeURIComponent(query)}&accept-language=${lang}`
    const res = await fetch(url)

    if (res.status === 429) {
      this.renderResults([{ label: "Too many requests. Please try again later.", class: "muted" }])
      this.isSearching = false
      return []
    }

    return res.json()
  }

  renderResults(items) {
    if (!this.hasResultsTarget) return

    if (!items?.length) {
      this.resultsTarget.innerHTML = ""
      this.resultsTarget.classList.add("hidden")
      return
    }

    this.resultsTarget.innerHTML = items
      .map((item, idx) =>
        item.class === "muted"
          ? `<div class="p-3 text-sm text-gray-500 text-center">${escapeHtml(item.label)}</div>`
          : `<button type="button" data-action="click->geolocation#selectResult" data-idx="${idx}" class="w-full text-left p-3 hover:bg-gray-100 text-sm border-b last:border-b-0 transition">
              <div class="font-medium text-gray-800">${escapeHtml(item.label)}</div>
            </button>`
      )
      .join("")

    this.resultsTarget.classList.remove("hidden")
    this.lastSearchResults = items
  }

  selectResult(e) {
    e.preventDefault()
    const idx = parseInt(e.currentTarget.dataset.idx, 10)
    const item = this.lastSearchResults?.[idx]

    if (!item || !this.hasInputTarget) return

    this.setCoordinates(item.lat, item.lon)
    this.clearResults()
    this.dispatch("success", { detail: { lat: item.lat, lng: item.lon, place: item.label } })
  }

  selectResultByIndex(idx) {
    const item = this.lastSearchResults[idx]
    if (item) {
      this.setCoordinates(item.lat, item.lon)
      this.clearResults()
      this.dispatch("success", { detail: { lat: item.lat, lng: item.lon, place: item.label } })
    }
  }

  onEnter(e) {
    const val = this.inputTarget.value.trim()
    if (!val || this.isCoordinates(val)) return

    e.preventDefault()
    if (this.lastSearchResults.length > 0) {
      this.selectResultByIndex(0)
    } else {
      this.searchCity(val)
    }
  }

  onFormSubmit(e) {
    if (!this.hasInputTarget) return
    const input = this.inputTarget.value.trim()

    if (!input || this.isCoordinates(input)) return

    e.preventDefault()
    this.lastSearchResults.length > 0 ? null : this.searchCity(input)
  }

  clearResults() {
    this.cancelResultsClear()
    if (this.hasResultsTarget) {
      this.resultsTarget.innerHTML = ""
      this.resultsTarget.classList.add("hidden")
    }
    this.lastSearchResults = []
  }
}

function escapeHtml(unsafe) {
  return String(unsafe)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;")
}
