import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["slide", "dot", "photosView", "mapView", "togglePhotosBtn", "toggleMapBtn"]
  static values = {
    interval: { type: Number, default: 4000 }
  }

  connect() {
    this.index = 0
    this.showingMap = false
    this.showSlide(0)
    this.startAutoplay()
  }

  disconnect() {
    this.stopAutoplay()
  }

  next() {
    if (this.slideTargets.length <= 1) return
    this.showSlide((this.index + 1) % this.slideTargets.length)
    this.restartAutoplay()
  }

  prev() {
    if (this.slideTargets.length <= 1) return
    this.showSlide((this.index - 1 + this.slideTargets.length) % this.slideTargets.length)
    this.restartAutoplay()
  }

  goTo(event) {
    const idx = parseInt(event.currentTarget.dataset.index, 10)
    if (Number.isNaN(idx)) return
    this.showSlide(idx)
    this.restartAutoplay()
  }

  pause() {
    this.stopAutoplay()
  }

  resume() {
    if (!this.showingMap) this.startAutoplay()
  }

  showPhotos() {
    this.showingMap = false
    if (this.hasPhotosViewTarget) this.photosViewTarget.classList.remove("hidden")
    if (this.hasMapViewTarget) this.mapViewTarget.classList.add("hidden")
    this.updateToggleButtons()
    this.startAutoplay()
  }

  showMap() {
    this.showingMap = true
    this.stopAutoplay()
    if (this.hasPhotosViewTarget) this.photosViewTarget.classList.add("hidden")
    if (this.hasMapViewTarget) this.mapViewTarget.classList.remove("hidden")
    this.updateToggleButtons()
    window.dispatchEvent(new Event("resize"))
  }

  showSlide(idx) {
    this.index = idx
    this.slideTargets.forEach((slide, i) => {
      const active = i === idx
      slide.classList.toggle("opacity-100", active)
      slide.classList.toggle("opacity-0", !active)
      slide.classList.toggle("pointer-events-none", !active)
    })
    this.dotTargets.forEach((dot, i) => {
      const active = i === idx
      dot.classList.toggle("bg-white", active)
      dot.classList.toggle("w-4", active)
      dot.classList.toggle("bg-white/50", !active)
      dot.classList.toggle("w-1.5", !active)
    })
  }

  updateToggleButtons() {
    if (this.hasTogglePhotosBtnTarget && this.hasToggleMapBtnTarget) {
      this.togglePhotosBtnTarget.classList.toggle("bg-white", !this.showingMap)
      this.togglePhotosBtnTarget.classList.toggle("text-gray-900", !this.showingMap)
      this.togglePhotosBtnTarget.classList.toggle("text-white", this.showingMap)

      this.toggleMapBtnTarget.classList.toggle("bg-white", this.showingMap)
      this.toggleMapBtnTarget.classList.toggle("text-gray-900", this.showingMap)
      this.toggleMapBtnTarget.classList.toggle("text-white", !this.showingMap)
    }
  }

  startAutoplay() {
    this.stopAutoplay()
    if (this.slideTargets.length <= 1 || this.showingMap) return
    this.timer = setInterval(() => {
      this.showSlide((this.index + 1) % this.slideTargets.length)
    }, this.intervalValue)
  }

  stopAutoplay() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }
}
