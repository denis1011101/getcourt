import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["map", "coordinates"]
  static values = {
    defaultLat: { type: Number, default: 56.838011 }, // Yekaterinburg
    defaultLng: { type: Number, default: 60.597465 },
    defaultZoom: { type: Number, default: 12 }
  }

  connect() {
    this.initMap()
  }

  async initMap() {
    if (!window.google || !window.google.maps) {
      // Ждём загрузки Google Maps API
      await new Promise(resolve => {
        window.initMap = resolve
        if (window.google && window.google.maps) resolve()
      })
    }

    const initial = this._readCoords(this.coordinatesTarget.value)
    const lat = initial?.lat ?? this.defaultLatValue
    const lng = initial?.lng ?? this.defaultLngValue

    this.map = new google.maps.Map(this.mapTarget, {
      center: { lat, lng },
      zoom: this.defaultZoomValue,
      mapTypeId: google.maps.MapTypeId.ROADMAP
    })

    this.marker = new google.maps.Marker({
      position: { lat, lng },
      map: this.map,
      draggable: true
    })

    this.marker.addListener("dragend", (e) => {
      const pos = e.latLng
      this._setPoint(pos.lat(), pos.lng())
    })

    this.map.addListener("click", (e) => {
      this.marker.setPosition(e.latLng)
      this._setPoint(e.latLng.lat(), e.latLng.lng())
    })

    if (!initial) this._writeCoords(lat, lng)
  }

  syncFromInput() {
    const raw = this.coordinatesTarget.value.trim()
    if (!raw) {
      this._setInvalidState(false)
      return
    }

    const c = this._readCoords(raw)
    if (!c) return

    this._setInvalidState(false)
    if (!this.map || !this.marker) return

    const pos = new google.maps.LatLng(c.lat, c.lng)
    this.marker.setPosition(pos)
    this.map.panTo(pos)
  }

  normalizeInput() {
    const raw = this.coordinatesTarget.value.trim()
    if (!raw) {
      this._setInvalidState(false)
      return
    }

    const c = this._readCoords(raw)
    if (!c) {
      this._setInvalidState(true)
      return
    }

    this._setInvalidState(false)
    this._writeCoords(c.lat, c.lng)
  }

  geolocate() {
    if (!navigator.geolocation || !this.map) return
    navigator.geolocation.getCurrentPosition((pos) => {
      const { latitude, longitude } = pos.coords
      const latLng = new google.maps.LatLng(latitude, longitude)
      this.marker.setPosition(latLng)
      this.map.setCenter(latLng)
      this.map.setZoom(14)
      this._setPoint(latitude, longitude)
    })
  }

  _setPoint(lat, lng) {
    this._setInvalidState(false)
    this._writeCoords(lat, lng)
  }

  _writeCoords(lat, lng) {
    this.coordinatesTarget.value = `${lat.toFixed(6)}, ${lng.toFixed(6)}`
  }

  _readCoords(v) {
    if (!v) return null
    const parts = v.trim().split(/[\s,;]+/)
    if (parts.length !== 2) return null

    const lat = Number(parts[0])
    const lng = Number(parts[1])
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null

    return { lat, lng }
  }

  _setInvalidState(invalid) {
    this.coordinatesTarget.classList.toggle("border-red-500", invalid)
    this.coordinatesTarget.classList.toggle("dark:border-red-400", invalid)
  }

  disconnect() {
    // Google Maps не требует специальной очистки
  }
}
