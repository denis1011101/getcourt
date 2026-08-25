import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button", "results"]
  static values = {
    unsupported: String,
    permissionDenied: String,
    unavailable: String,
    timeout: String,
    failed: String,
    locating: String,
    useLocation: String,
    searching: String,
    noResults: String,
    searchError: String,
    rateLimited: String
  }

  connect() {
    this.isLocating = false
    this.isSearching = false
    this.searchTimeout = null
    this.clearResultsTimeout = null
    this.selectableResults = []

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
      !navigator.geolocation && window.alert(this.unsupportedValue)
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
      [err.PERMISSION_DENIED]: this.permissionDeniedValue,
      [err.POSITION_UNAVAILABLE]: this.unavailableValue,
      [err.TIMEOUT]: this.timeoutValue
    }
    return messages[err.code] || this.failedValue
  }

  updateButton(disabled) {
    if (!this.hasButtonTarget) return
    this.buttonTarget.disabled = disabled
    if (disabled) {
      this.buttonTarget.dataset.prevText ||= this.buttonTarget.textContent
      this.buttonTarget.textContent = this.locatingValue
    } else {
      this.buttonTarget.textContent = this.buttonTarget.dataset.prevText || this.useLocationValue
      delete this.buttonTarget.dataset.prevText
    }
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
    this.renderResults([{ label: this.searchingValue, class: "muted" }])

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
          : [{ label: this.noResultsValue, class: "muted" }]
      )
    } catch (err) {
      console.warn("Geocoding error:", err)
      this.renderResults([{ label: this.searchErrorValue, class: "muted" }])
    } finally {
      this.isSearching = false
    }
  }

  async fetchResults(query, lang) {
    const url = `https://nominatim.openstreetmap.org/search?format=json&addressdetails=1&limit=5&q=${encodeURIComponent(query)}&accept-language=${lang}`
    const res = await fetch(url)

    if (res.status === 429) {
      this.renderResults([{ label: this.rateLimitedValue, class: "muted" }])
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
      this.selectableResults = []
      return
    }

    // Служебные строки («Ищу…», «Ничего не найдено») рисуем, но выбирать их нельзя:
    // data-idx считаем по выбираемым элементам, их же и запоминаем.
    const selectable = []

    this.resultsTarget.innerHTML = items
      .map((item) => {
        if (!isSelectableResult(item)) {
          return `<div class="p-3 text-sm text-gray-500 text-center">${escapeHtml(item.label)}</div>`
        }

        const idx = selectable.push(item) - 1
        return `<button type="button" data-action="click->geolocation#selectResult" data-idx="${idx}" class="w-full text-left p-3 hover:bg-gray-100 text-sm border-b last:border-b-0 transition">
              <div class="font-medium text-gray-800">${escapeHtml(item.label)}</div>
            </button>`
      })
      .join("")

    this.resultsTarget.classList.remove("hidden")
    this.selectableResults = selectable
  }

  selectResult(e) {
    e.preventDefault()
    const idx = parseInt(e.currentTarget.dataset.idx, 10)
    const item = this.selectableResults?.[idx]

    if (!item || !this.hasInputTarget) return

    this.setCoordinates(item.lat, item.lon)
    this.clearResults()
    this.dispatch("success", { detail: { lat: item.lat, lng: item.lon, place: item.label } })
  }

  selectResultByIndex(idx) {
    const item = this.selectableResults[idx]
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
    if (this.selectableResults.length > 0) {
      this.selectResultByIndex(0)
    } else {
      this.searchCity(val)
    }
  }

  clearResults() {
    this.cancelResultsClear()
    if (this.hasResultsTarget) {
      this.resultsTarget.innerHTML = ""
      this.resultsTarget.classList.add("hidden")
    }
    this.selectableResults = []
  }
}

function isSelectableResult(item) {
  return item?.class !== "muted" && Number.isFinite(item?.lat) && Number.isFinite(item?.lon)
}

function escapeHtml(unsafe) {
  return String(unsafe)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;")
}
