import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]

  connect() {
    this.isLocating = false
  }

  locate() {
    if (this.isLocating) return // Предотвращаем повторные клики

    const hasBtn = this.hasButtonTarget
    const hasInput = this.hasInputTarget
    const btn = hasBtn ? this.buttonTarget : null
    const input = hasInput ? this.inputTarget : null

    if (!input) {
      console.warn("GeolocationController: input target not found")
      return
    }

    if (!navigator.geolocation) {
      window.alert("Geolocation is not supported by your browser.")
      return
    }

    this.isLocating = true

    if (btn) {
      btn.disabled = true
      btn.dataset.prevText = btn.textContent
      btn.textContent = "Locating..."
    }

    input.value = ""

    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const { latitude, longitude } = pos.coords
        const coordsStr = `${latitude.toFixed(6)},${longitude.toFixed(6)}`
        input.value = coordsStr

        if (btn) {
          btn.disabled = false
          btn.textContent = btn.dataset.prevText || "Use my location"
        }

        this.isLocating = false
        this.dispatch("success", { detail: { lat: latitude, lng: longitude } })
      },
      (err) => {
        if (btn) {
          btn.disabled = false
          btn.textContent = btn.dataset.prevText || "Use my location"
        }
        console.warn("GeolocationController error:", err)

        let message = "Failed to get location."
        switch (err.code) {
          case err.PERMISSION_DENIED:
            message = "Location access denied. Please allow location access in your browser settings."
            break
          case err.POSITION_UNAVAILABLE:
            message = "Location information is unavailable."
            break
          case err.TIMEOUT:
            message = "Location request timed out."
            break
        }
        window.alert(message)
        this.isLocating = false
        this.dispatch("error", { detail: { error: err } })
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 } // Увеличил таймаут
    )
  }
}