import { Controller } from "@hotwired/stimulus"

// Выбор нескольких кортов: те же фильтры страна/город, что у формы игры, плюс
// поиск по названию. Отмеченные корты не прячутся фильтром — иначе выбор
// незаметно уезжает из виду, а отправляется он всё равно.
export default class extends Controller {
  static targets = ["country", "city", "search", "option", "group", "empty", "count", "clear"]
  static values = { countryCities: Object, cityPlaceholder: String, countLabel: String }

  connect() {
    this.filter()
  }

  countryChanged() {
    this.syncCityOptions()
    this.filter()
  }

  filter() {
    const country = this.hasCountryTarget ? this.countryTarget.value : ""
    const city = this.hasCityTarget ? this.cityTarget.value : ""
    const query = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : ""

    let visible = 0
    this.optionTargets.forEach((option) => {
      const checked = option.querySelector("input[type=checkbox]").checked
      const shown = checked || this.matches(option.dataset, country, city, query)
      option.hidden = !shown
      if (shown) visible += 1
    })

    // Заголовок города прячем вместе с его кортами.
    this.groupTargets.forEach((group) => {
      group.hidden = !this.optionTargets.some((option) => !option.hidden && option.dataset.city === group.dataset.city)
    })

    if (this.hasEmptyTarget) this.emptyTarget.hidden = visible > 0
    this.updateCount()
  }

  // Снятая галка может не подходить под фильтр — пересчитываем сразу, чтобы
  // список не остался с «чужим» кортом.
  toggled() {
    this.filter()
  }

  clear() {
    this.optionTargets.forEach((option) => { option.querySelector("input[type=checkbox]").checked = false })
    this.filter()
  }

  matches(data, country, city, query) {
    if (city && data.city !== city) return false
    if (!city && country && data.country !== country) return false
    return !query || data.name.includes(query)
  }

  updateCount() {
    const selected = this.optionTargets.filter((option) => option.querySelector("input[type=checkbox]").checked).length
    if (this.hasCountTarget) this.countTarget.textContent = this.countLabelValue.replace("%{count}", selected)
    if (this.hasClearTarget) this.clearTarget.hidden = selected === 0
  }

  syncCityOptions() {
    if (!this.hasCityTarget) return

    const cities = this.countryCitiesValue[this.countryTarget.value] || []
    const previous = this.cityTarget.value
    this.cityTarget.innerHTML = ""
    this.cityTarget.appendChild(new Option(this.cityPlaceholderValue, ""))
    cities.forEach((name) => this.cityTarget.appendChild(new Option(name, name)))
    this.cityTarget.value = cities.includes(previous) ? previous : ""
  }
}
