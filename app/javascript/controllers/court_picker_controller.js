import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["map", "select"]
  static values = {
    courts: Array,
    defaultLat: { type: Number, default: 56.838011 }, // Yekaterinburg
    defaultLng: { type: Number, default: 60.597465 },
    defaultZoom: { type: Number, default: 12 }
  }

  connect() {
    this.initMap()
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

    if (this.selectTarget.value) this._focusSelected()
  }

  selectChanged() {
    this._focusSelected()
  }

  _focusSelected() {
    const marker = this.markersById.get(String(this.selectTarget.value))
    if (!marker || !this.map) return
    this.map.setCenter(marker.getPosition())
    this.map.setZoom(Math.max(this.map.getZoom(), 14))
    // Можно открыть infoWindow, но для простоты пропустим
  }

  _center() {
    const withCoords = (this.courtsValue || []).find(this._valid)
    return withCoords ? [withCoords.lat, withCoords.lng] : [this.defaultLatValue, this.defaultLngValue]
  }

  _valid(c) {
    return c && Number.isFinite(c.lat) && Number.isFinite(c.lng)
  }

  disconnect() {
    // Очистка не требуется
  }
}