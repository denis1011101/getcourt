import { Controller } from "@hotwired/stimulus"

// Поле города в профиле. Сохранить можно только город из справочника, поэтому
// видимый текст сам по себе ничего не значит: город несёт hidden-поле с id, и
// любое ручное редактирование текста этот id сбрасывает — иначе к новому тексту
// прицепился бы id старого выбора.
export default class extends Controller {
  static targets = ["input", "cityId", "results"]
  static values = {
    url: String,
    searching: String,
    noMatches: String,
    error: String
  }

  connect() {
    this.searchTimeout = null
    this.hideTimeout = null
    this.onDocumentClick = (event) => {
      if (!this.element.contains(event.target)) this.hide()
    }
    document.addEventListener("click", this.onDocumentClick)
  }

  disconnect() {
    clearTimeout(this.searchTimeout)
    clearTimeout(this.hideTimeout)
    document.removeEventListener("click", this.onDocumentClick)
  }

  search() {
    this.cityIdTarget.value = ""
    clearTimeout(this.searchTimeout)

    const query = this.inputTarget.value.trim()
    if (query.length < 2) {
      this.hide()
      return
    }

    this.searchTimeout = setTimeout(() => this.fetchCities(query), 300)
  }

  async fetchCities(query) {
    this.renderMessage(this.searchingValue)
    this.requestId = (this.requestId || 0) + 1
    const requestId = this.requestId

    try {
      const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`, {
        headers: { Accept: "application/json" }
      })
      if (!response.ok) throw new Error(response.status)
      const cities = await response.json()
      // Ответы могут прийти не в том порядке, в каком уходили запросы.
      if (requestId !== this.requestId) return
      this.renderCities(cities)
    } catch (error) {
      console.warn("City search failed:", error)
      if (requestId === this.requestId) this.renderMessage(this.errorValue)
    }
  }

  renderCities(cities) {
    if (!cities.length) {
      this.renderMessage(this.noMatchesValue)
      return
    }

    this.resultsTarget.innerHTML = cities
      .map(
        (city) => `
          <button type="button" data-action="click->city-picker#select"
                  data-id="${city.id}" data-name="${escapeAttribute(city.name)}"
                  class="block w-full border-b px-3 py-2 text-left text-sm last:border-b-0 hover:bg-gray-100 dark:border-white/10 dark:hover:bg-white/5">
            <span class="font-medium">${escapeHtml(city.name)}</span>
            <span class="ml-1 text-xs text-gray-500 dark:text-slate-400">${escapeHtml(city.hint)}</span>
          </button>`
      )
      .join("")
    this.show()
  }

  renderMessage(text) {
    this.resultsTarget.innerHTML = `<div class="px-3 py-2 text-center text-sm text-gray-500 dark:text-slate-400">${escapeHtml(text)}</div>`
    this.show()
  }

  select(event) {
    const { id, name } = event.currentTarget.dataset
    this.cityIdTarget.value = id
    this.inputTarget.value = name
    this.hide()
  }

  show() {
    this.resultsTarget.classList.remove("hidden")
  }

  hide() {
    this.resultsTarget.classList.add("hidden")
  }
}

function escapeHtml(value) {
  const div = document.createElement("div")
  div.textContent = value == null ? "" : String(value)
  return div.innerHTML
}

function escapeAttribute(value) {
  return escapeHtml(value).replace(/"/g, "&quot;")
}
