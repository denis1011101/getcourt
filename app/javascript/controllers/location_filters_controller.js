import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["country", "city"]
  static values = { countryCities: Object }

  connect() {
    this.syncCityOptions()
  }

  countryChanged() {
    this.syncCityOptions()
  }

  syncCityOptions() {
    if (!this.hasCountryTarget || !this.hasCityTarget) return

    const selectedCountry = this.countryTarget.value || ""
    const selectedCity = this.cityTarget.value
    const cities = this.countryCitiesValue[selectedCountry] || []

    this.cityTarget.innerHTML = ""
    this.cityTarget.appendChild(this.buildOption("", this.cityTarget.dataset.placeholder || ""))

    cities.forEach((city) => {
      this.cityTarget.appendChild(this.buildOption(city, city))
    })

    if (cities.includes(selectedCity)) {
      this.cityTarget.value = selectedCity
    } else {
      this.cityTarget.value = ""
    }
  }

  buildOption(value, label) {
    const option = document.createElement("option")
    option.value = value
    option.textContent = label
    return option
  }
}
