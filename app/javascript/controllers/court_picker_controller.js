import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["map", "select", "surfaceSelect", "environmentSelect", "countrySelect", "citySelect"]
  static values = {
    courts: Array,
    countryCities: Object,
    cityPlaceholder: String,
    surfaceLabels: Object,
    environmentLabels: Object,
    surfaceSelected: String,
    environmentSelected: String,
    defaultLat: { type: Number, default: 56.838011 }, // Yekaterinburg
    defaultLng: { type: Number, default: 60.597465 },
    defaultZoom: { type: Number, default: 12 }
  }

  connect() {
    this.filterCourts()
    this.initMap()
    this.updateSurfaceOptions({ initial: true })
  }

  async initMap() {
    if (!window.google || !window.google.maps) {
      await new Promise(resolve => {
        window.initMap = resolve
        if (window.google && window.google.maps) resolve()
      })
    }

    const center = this._center()
    this.map = new google.maps.Map(this.mapTarget, {
      center: { lat: center[0], lng: center[1] },
      zoom: this.defaultZoomValue,
      mapTypeId: google.maps.MapTypeId.ROADMAP
    })

    this.markersById = new Map()
    ;(this.courtsValue || []).forEach(c => {
      if (!this._valid(c)) return
      const marker = new google.maps.Marker({
        position: { lat: c.lat, lng: c.lng },
        map: this.map,
        title: c.name
      })
      marker.addListener("click", () => {
        this.selectTarget.value = String(c.id)
        this.selectTarget.dispatchEvent(new Event("change", { bubbles: true }))
      })
      this.markersById.set(String(c.id), marker)
    })

    this._syncMarkers()
    if (this.selectTarget.value) this._focusSelected()
  }

  // Смена страны или города: пересобираем города под страну и список кортов.
  locationChanged(event) {
    if (this.hasCountrySelectTarget && event.target === this.countrySelectTarget) this._syncCityOptions()
    this.filterCourts()
  }

  selectChanged() {
    this._focusSelected()
    this.updateSurfaceOptions()
  }

  // Оставляет в списке корты выбранной страны/города, группируя их по городам.
  // Если выбранный корт отфильтровался, берём первый доступный.
  filterCourts() {
    const country = this.hasCountrySelectTarget ? this.countrySelectTarget.value : ""
    const city = this.hasCitySelectTarget ? this.citySelectTarget.value : ""
    const previous = this.selectTarget.value
    const courts = (this.courtsValue || []).filter(c => this._matchesLocation(c, country, city))
    const groups = this._groupByCity(courts)
    // Города разделяем заголовками только когда их несколько — иначе это лишний шум.
    const grouped = groups.length > 1

    this.selectTarget.innerHTML = ""
    groups.forEach(([cityName, cityCourts]) => {
      const parent = grouped && cityName ? this._appendGroup(cityName) : this.selectTarget
      cityCourts.forEach(c => parent.appendChild(this._buildOption(String(c.id), c.name)))
    })

    // Порядок опций задают группы, поэтому запасной вариант берём из самого списка.
    const stillListed = courts.some(c => String(c.id) === String(previous))
    if (stillListed) this.selectTarget.value = previous
    else this.selectTarget.selectedIndex = 0

    this._syncMarkers()
    if (!stillListed) {
      this.updateSurfaceOptions()
      this._focusSelected()
    }
  }

  // Заполняет селекты покрытия и среды вариантами выбранного корта.
  // preselect (сохранённое значение игры) применяется только при initial connect;
  // после смены корта пользователем ориентируемся только на текущее значение селекта.
  updateSurfaceOptions({ initial = false } = {}) {
    const court = (this.courtsValue || []).find(c => String(c.id) === String(this.selectTarget.value))

    if (this.hasSurfaceSelectTarget) {
      this._fillSelect(
        this.surfaceSelectTarget,
        (court && court.surfaces) || [],
        this.surfaceLabelsValue || {},
        initial ? this.surfaceSelectedValue : ""
      )
    }

    if (this.hasEnvironmentSelectTarget) {
      this._fillSelect(
        this.environmentSelectTarget,
        (court && court.environments) || [],
        this.environmentLabelsValue || {},
        initial ? this.environmentSelectedValue : ""
      )
    }
  }

  _matchesLocation(court, country, city) {
    if (city) return court.city === city
    if (country) return court.country === country
    return true
  }

  _groupByCity(courts) {
    const groups = new Map()
    courts.forEach(c => {
      const key = c.city || ""
      if (!groups.has(key)) groups.set(key, [])
      groups.get(key).push(c)
    })

    return [...groups.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([cityName, cityCourts]) => [cityName, cityCourts.sort((a, b) => a.name.localeCompare(b.name))])
  }

  _appendGroup(label) {
    const group = document.createElement("optgroup")
    group.label = label
    this.selectTarget.appendChild(group)
    return group
  }

  _syncCityOptions() {
    if (!this.hasCitySelectTarget) return

    const selectedCity = this.citySelectTarget.value
    const cities = (this.countryCitiesValue || {})[this.countrySelectTarget.value] || []

    this.citySelectTarget.innerHTML = ""
    this.citySelectTarget.appendChild(this._buildOption("", this.cityPlaceholderValue))
    cities.forEach(city => this.citySelectTarget.appendChild(this._buildOption(city, city)))
    this.citySelectTarget.value = cities.includes(selectedCity) ? selectedCity : ""
  }

  // Маркеры отфильтрованных кортов убираем с карты, чтобы она совпадала со списком.
  _syncMarkers() {
    if (!this.markersById || !this.map) return

    const listed = new Set([...this.selectTarget.options].map(option => option.value))
    this.markersById.forEach((marker, id) => marker.setMap(listed.has(id) ? this.map : null))
  }

  _buildOption(value, label) {
    const option = document.createElement("option")
    option.value = value
    option.textContent = label
    return option
  }

  _fillSelect(select, values, labels, preselect) {
    const previous = select.value || preselect || ""
    const blank = select.querySelector('option[value=""]')
    select.innerHTML = ""
    if (blank) select.appendChild(blank)

    values.forEach(value => {
      const option = document.createElement("option")
      option.value = value
      option.textContent = labels[value] || value
      select.appendChild(option)
    })

    // Сохраняем прежний выбор, если он всё ещё доступен
    select.value = values.includes(previous) ? previous : ""
  }

  _focusSelected() {
    const marker = this.markersById && this.markersById.get(String(this.selectTarget.value))
    if (!marker || !this.map) return
    this.map.setCenter(marker.getPosition())
    this.map.setZoom(Math.max(this.map.getZoom(), 14))
    // Можно открыть infoWindow, но для простоты пропустим
  }

  _center() {
    const selected = (this.courtsValue || []).find(c => String(c.id) === String(this.selectTarget.value))
    const withCoords = this._valid(selected) ? selected : (this.courtsValue || []).find(this._valid)
    return withCoords ? [withCoords.lat, withCoords.lng] : [this.defaultLatValue, this.defaultLngValue]
  }

  _valid(c) {
    return c && Number.isFinite(c.lat) && Number.isFinite(c.lng)
  }

  disconnect() {
    // Очистка не требуется
  }
}
