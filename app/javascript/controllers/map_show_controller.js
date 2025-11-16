import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    lat: Number,
    lng: Number,
    zoom: { type: Number, default: 14 }
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

    const lat = this.latValue || 0
    const lng = this.lngValue || 0
    this.map = new google.maps.Map(this.element, {
      center: { lat, lng },
      zoom: this.zoomValue,
      mapTypeId: google.maps.MapTypeId.ROADMAP,
      disableDefaultUI: true, // Убираем контролы для статичной карты
      zoomControl: false,
      draggable: false
    })

    if (Number.isFinite(lat) && Number.isFinite(lng)) {
      new google.maps.Marker({
        position: { lat, lng },
        map: this.map
      })
    }
  }

  disconnect() {
    // Очистка не требуется
  }
}