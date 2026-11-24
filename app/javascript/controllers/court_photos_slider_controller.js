import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "viewport",
    "slide",
    "mapSlide",
    "mapOverlay",
    "dot",
    "togglePhotosBtn",
    "toggleMapBtn",
    "lightbox",
    "lightboxSlide",
    "lightboxMapSlide",
    "lightboxMapContainer",
    "lightboxCounter",
    "lightboxDot",
    "lightboxTogglePhotosBtn",
    "lightboxToggleMapBtn"
  ]

  static values = {
    interval: { type: Number, default: 4500 },
    lat: { type: Number, default: 0 },
    lng: { type: Number, default: 0 },
    hasMap: { type: Boolean, default: false }
  }

  connect() {
    this.currentIndex = 0
    this.lightboxCurrentIndex = 0
    this.lastPhotoIndex = 0
    this.isShowingMap = false
    this.isLightboxOpen = false
    this.isHovering = false
    this.fullscreenMapInitialized = false
    this.fullscreenMap = null
    this.mapCheckInterval = null

    this.showSlide(0)
    this.startAutoplay()

    this.boundKeydown = this.onKeydown.bind(this)
    window.addEventListener("keydown", this.boundKeydown)

    this.setupViewportTouchListeners()
    this.setupLightboxTouchListeners()
  }

  disconnect() {
    this.stopAutoplay()
    window.removeEventListener("keydown", this.boundKeydown)

    if (this.viewportTouchCleanup) {
      this.viewportTouchCleanup()
      this.viewportTouchCleanup = null
    }

    if (this.lightboxTouchCleanup) {
      this.lightboxTouchCleanup()
      this.lightboxTouchCleanup = null
    }

    if (this.mapCheckInterval) {
      clearInterval(this.mapCheckInterval)
      this.mapCheckInterval = null
    }

    if (this.isLightboxOpen) {
      document.body.classList.remove("overflow-hidden")
      if (this.hasLightboxTarget) {
        this.lightboxTarget.classList.add("hidden")
      }
      this.isLightboxOpen = false
    }
  }

  get photoCount() {
    return this.hasSlideTarget ? this.slideTargets.length : 0
  }

  get canShowMap() {
    return this.hasMapValue && this.hasMapSlideTarget
  }

  get totalSlides() {
    return this.photoCount + (this.canShowMap ? 1 : 0)
  }

  get mapIndex() {
    return this.canShowMap ? this.photoCount : -1
  }

  next() {
    if (this.totalSlides <= 1) return
    this.showSlide(this.currentIndex + 1)
    this.startAutoplay()
  }

  prev() {
    if (this.totalSlides <= 1) return
    this.showSlide(this.currentIndex - 1)
    this.startAutoplay()
  }

  goTo(event) {
    const idx = parseInt(event.currentTarget.dataset.index, 10)
    if (Number.isNaN(idx)) return
    this.showSlide(idx)
    this.startAutoplay()
  }

  onMouseEnter() {
    this.isHovering = true
    this.pause()
  }

  onMouseLeave() {
    this.isHovering = false
    this.resume()
  }

  pause() {
    this.stopAutoplay()
  }

  resume() {
    if (!this.isLightboxOpen && !this.isHovering) {
      this.startAutoplay()
    }
  }

  showPhotos() {
    const target = this.photoCount > 0 ? (this.lastPhotoIndex || 0) : 0
    this.showSlide(target)
    this.startAutoplay()
  }

  showMap() {
    if (this.canShowMap) {
      this.showSlide(this.mapIndex)
      this.startAutoplay()
    }
  }

  showSlide(idx) {
    if (this.totalSlides === 0) return

    const normalizedIndex = ((idx % this.totalSlides) + this.totalSlides) % this.totalSlides
    this.currentIndex = normalizedIndex
    const isMap = this.canShowMap && normalizedIndex === this.mapIndex

    if (!isMap) {
      this.lastPhotoIndex = normalizedIndex
      this.isShowingMap = false

      this.slideTargets.forEach((slide, i) => {
        const active = i === normalizedIndex
        slide.classList.toggle("opacity-100", active)
        slide.classList.toggle("opacity-0", !active)
        slide.classList.toggle("pointer-events-none", !active)
        slide.setAttribute("tabindex", active ? "0" : "-1")
        slide.setAttribute("aria-hidden", (!active).toString())
      })

      if (this.hasMapSlideTarget) {
        this.mapSlideTarget.classList.add("opacity-0", "pointer-events-none")
        this.mapSlideTarget.classList.remove("opacity-100", "pointer-events-auto")
        this.mapSlideTarget.setAttribute("aria-hidden", "true")
      }

      if (this.hasMapOverlayTarget) {
        this.mapOverlayTarget.setAttribute("tabindex", "-1")
        this.mapOverlayTarget.setAttribute("aria-hidden", "true")
      }
    } else {
      this.isShowingMap = true

      this.slideTargets.forEach(slide => {
        slide.classList.add("opacity-0", "pointer-events-none")
        slide.classList.remove("opacity-100")
        slide.setAttribute("tabindex", "-1")
        slide.setAttribute("aria-hidden", "true")
      })

      if (this.hasMapSlideTarget) {
        this.mapSlideTarget.classList.remove("opacity-0", "pointer-events-none")
        this.mapSlideTarget.classList.add("opacity-100", "pointer-events-auto")
        this.mapSlideTarget.setAttribute("aria-hidden", "false")
        window.dispatchEvent(new Event("resize"))
      }

      if (this.hasMapOverlayTarget) {
        this.mapOverlayTarget.setAttribute("tabindex", "0")
        this.mapOverlayTarget.setAttribute("aria-hidden", "false")
      }
    }

    this.updateDots(normalizedIndex)
    this.updateToggleButtons()
  }

  updateDots(activeIndex) {
    this.dotTargets.forEach((dot, i) => {
      const active = i === activeIndex
      dot.classList.toggle("bg-[#ffffff]", active)
      dot.classList.toggle("w-5", active)
      dot.classList.toggle("bg-white/40", !active)
      dot.classList.toggle("w-1.5", !active)
    })
  }

  updateToggleButtons() {
    if (this.hasTogglePhotosBtnTarget && this.hasToggleMapBtnTarget) {
      const onMap = this.isShowingMap
      this.togglePhotosBtnTarget.classList.toggle("bg-[#ffffff]", !onMap)
      this.togglePhotosBtnTarget.classList.toggle("text-[#0f172a]", !onMap)
      this.togglePhotosBtnTarget.classList.toggle("font-semibold", !onMap)
      this.togglePhotosBtnTarget.classList.toggle("shadow-sm", !onMap)
      this.togglePhotosBtnTarget.classList.toggle("text-white/80", onMap)
      this.togglePhotosBtnTarget.classList.toggle("hover:text-white", onMap)
      this.togglePhotosBtnTarget.setAttribute("aria-selected", (!onMap).toString())

      this.toggleMapBtnTarget.classList.toggle("bg-[#ffffff]", onMap)
      this.toggleMapBtnTarget.classList.toggle("text-[#0f172a]", onMap)
      this.toggleMapBtnTarget.classList.toggle("font-semibold", onMap)
      this.toggleMapBtnTarget.classList.toggle("shadow-sm", onMap)
      this.toggleMapBtnTarget.classList.toggle("text-white/80", !onMap)
      this.toggleMapBtnTarget.classList.toggle("hover:text-white", !onMap)
      this.toggleMapBtnTarget.setAttribute("aria-selected", onMap.toString())
    }
  }

  startAutoplay() {
    this.stopAutoplay()
    if (this.totalSlides <= 1 || this.isLightboxOpen || this.isHovering) return

    this.timer = setInterval(() => {
      this.next()
    }, this.intervalValue)
  }

  stopAutoplay() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  // --- Viewport Touch Gestures ---
  setupViewportTouchListeners() {
    const el = this.hasViewportTarget ? this.viewportTarget : this.element

    let startX = 0
    let startY = 0
    let deltaX = 0
    let isTracking = false

    const onTouchStart = (e) => {
      if (e.touches.length !== 1) return
      startX = e.touches[0].clientX
      startY = e.touches[0].clientY
      deltaX = 0
      isTracking = true
      this.pause()
    }

    const onTouchMove = (e) => {
      if (!isTracking || e.touches.length !== 1) return
      deltaX = e.touches[0].clientX - startX
      const deltaY = e.touches[0].clientY - startY
      if (Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > 10) {
        if (e.cancelable) e.preventDefault()
      }
    }

    const onTouchEnd = () => {
      if (!isTracking) return
      isTracking = false
      const threshold = 40
      if (deltaX < -threshold) {
        this.next()
      } else if (deltaX > threshold) {
        this.prev()
      }
      startX = 0
      deltaX = 0
      this.resume()
    }

    const onTouchCancel = () => {
      isTracking = false
      startX = 0
      deltaX = 0
      this.resume()
    }

    el.addEventListener("touchstart", onTouchStart, { passive: true })
    el.addEventListener("touchmove", onTouchMove, { passive: false })
    el.addEventListener("touchend", onTouchEnd, { passive: true })
    el.addEventListener("touchcancel", onTouchCancel, { passive: true })

    this.viewportTouchCleanup = () => {
      el.removeEventListener("touchstart", onTouchStart)
      el.removeEventListener("touchmove", onTouchMove)
      el.removeEventListener("touchend", onTouchEnd)
      el.removeEventListener("touchcancel", onTouchCancel)
    }
  }

  // --- Lightbox Touch Gestures ---
  setupLightboxTouchListeners() {
    if (!this.hasLightboxTarget) return
    const el = this.lightboxTarget

    let startX = 0
    let startY = 0
    let deltaX = 0
    let isTracking = false

    const onTouchStart = (e) => {
      if (e.touches.length !== 1) return
      // If touch originates inside interactive Google Map container, do not hijack pan/zoom
      if (this.hasLightboxMapContainerTarget && this.lightboxMapContainerTarget.contains(e.target)) {
        isTracking = false
        return
      }
      startX = e.touches[0].clientX
      startY = e.touches[0].clientY
      deltaX = 0
      isTracking = true
    }

    const onTouchMove = (e) => {
      if (!isTracking || e.touches.length !== 1) return
      deltaX = e.touches[0].clientX - startX
      const deltaY = e.touches[0].clientY - startY
      if (Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > 10) {
        if (e.cancelable) e.preventDefault()
      }
    }

    const onTouchEnd = () => {
      if (!isTracking) return
      isTracking = false
      const threshold = 40
      if (deltaX < -threshold) {
        this.lightboxNext()
      } else if (deltaX > threshold) {
        this.lightboxPrev()
      }
      startX = 0
      deltaX = 0
    }

    const onTouchCancel = () => {
      isTracking = false
      startX = 0
      deltaX = 0
    }

    el.addEventListener("touchstart", onTouchStart, { passive: true })
    el.addEventListener("touchmove", onTouchMove, { passive: false })
    el.addEventListener("touchend", onTouchEnd, { passive: true })
    el.addEventListener("touchcancel", onTouchCancel, { passive: true })

    this.lightboxTouchCleanup = () => {
      el.removeEventListener("touchstart", onTouchStart)
      el.removeEventListener("touchmove", onTouchMove)
      el.removeEventListener("touchend", onTouchEnd)
      el.removeEventListener("touchcancel", onTouchCancel)
    }
  }

  // --- Fullscreen Lightbox Gallery ---
  openLightbox(event) {
    if (!this.hasLightboxTarget) return

    this.triggerElement = event?.currentTarget || document.activeElement

    let targetIndex = this.currentIndex
    if (event?.currentTarget?.dataset?.slideIndex !== undefined) {
      const parsed = parseInt(event.currentTarget.dataset.slideIndex, 10)
      if (!Number.isNaN(parsed)) targetIndex = parsed
    } else if (event?.currentTarget?.dataset?.openType === "map") {
      targetIndex = this.mapIndex >= 0 ? this.mapIndex : 0
    }

    this.isLightboxOpen = true
    this.stopAutoplay()
    document.body.classList.add("overflow-hidden")

    this.lightboxTarget.classList.remove("hidden")
    this.showLightboxSlide(targetIndex)

    setTimeout(() => {
      if (this.hasLightboxTarget) {
        this.lightboxTarget.focus()
      }
    }, 50)
  }

  closeLightbox() {
    if (!this.hasLightboxTarget) return

    this.isLightboxOpen = false
    this.lightboxTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")

    // Restore focus to opener element
    if (this.triggerElement && typeof this.triggerElement.focus === "function") {
      this.triggerElement.focus()
      this.triggerElement = null
    }

    // Sync inline slide with whatever was viewed in lightbox
    this.showSlide(this.lightboxCurrentIndex)
    if (!this.isHovering) {
      this.startAutoplay()
    }
  }

  onLightboxBackdropClick(event) {
    // If click is on interactive content (image, map, buttons, thumbs), don't close
    if (event.target.closest("[data-lightbox-content]")) {
      return
    }
    this.closeLightbox()
  }

  lightboxNext() {
    if (this.totalSlides <= 1) return
    this.showLightboxSlide(this.lightboxCurrentIndex + 1)
  }

  lightboxPrev() {
    if (this.totalSlides <= 1) return
    this.showLightboxSlide(this.lightboxCurrentIndex - 1)
  }

  goToLightbox(event) {
    const idx = parseInt(event.currentTarget.dataset.index, 10)
    if (Number.isNaN(idx)) return
    this.showLightboxSlide(idx)
  }

  showLightboxSlide(idx) {
    if (this.totalSlides === 0) return

    const normalizedIndex = ((idx % this.totalSlides) + this.totalSlides) % this.totalSlides
    this.lightboxCurrentIndex = normalizedIndex
    const isMap = this.canShowMap && normalizedIndex === this.mapIndex

    if (!isMap) {
      this.lastPhotoIndex = normalizedIndex

      this.lightboxSlideTargets.forEach((slide, i) => {
        const active = i === normalizedIndex
        slide.classList.toggle("opacity-100", active)
        slide.classList.toggle("opacity-0", !active)
        slide.classList.toggle("pointer-events-none", !active)
        slide.setAttribute("aria-hidden", (!active).toString())
      })

      if (this.hasLightboxMapSlideTarget) {
        this.lightboxMapSlideTarget.classList.add("opacity-0", "pointer-events-none")
        this.lightboxMapSlideTarget.classList.remove("opacity-100", "pointer-events-auto")
        this.lightboxMapSlideTarget.setAttribute("aria-hidden", "true")
      }

      if (this.hasLightboxCounterTarget) {
        const template = this.lightboxCounterTarget.dataset.counterTemplate
        if (template) {
          this.lightboxCounterTarget.textContent = template
            .replace("%{current}", (normalizedIndex + 1).toString())
            .replace("%{total}", this.photoCount.toString())
        } else {
          this.lightboxCounterTarget.textContent = `${normalizedIndex + 1} / ${this.photoCount}`
        }
      }
    } else {
      this.lightboxSlideTargets.forEach(slide => {
        slide.classList.add("opacity-0", "pointer-events-none")
        slide.classList.remove("opacity-100")
        slide.setAttribute("aria-hidden", "true")
      })

      if (this.hasLightboxMapSlideTarget) {
        this.lightboxMapSlideTarget.classList.remove("opacity-0", "pointer-events-none")
        this.lightboxMapSlideTarget.classList.add("opacity-100", "pointer-events-auto")
        this.lightboxMapSlideTarget.setAttribute("aria-hidden", "false")
        this.initFullscreenMap()
      }

      if (this.hasLightboxCounterTarget) {
        this.lightboxCounterTarget.textContent = this.lightboxCounterTarget.dataset.mapLabel || "Map"
      }
    }

    // Update lightbox toggle tabs
    if (this.hasLightboxTogglePhotosBtnTarget && this.hasLightboxToggleMapBtnTarget) {
      this.lightboxTogglePhotosBtnTarget.classList.toggle("bg-[#ffffff]", !isMap)
      this.lightboxTogglePhotosBtnTarget.classList.toggle("text-[#0f172a]", !isMap)
      this.lightboxTogglePhotosBtnTarget.classList.toggle("font-semibold", !isMap)
      this.lightboxTogglePhotosBtnTarget.classList.toggle("shadow-sm", !isMap)
      this.lightboxTogglePhotosBtnTarget.classList.toggle("text-white/80", isMap)
      this.lightboxTogglePhotosBtnTarget.classList.toggle("hover:text-white", isMap)
      this.lightboxTogglePhotosBtnTarget.setAttribute("aria-selected", (!isMap).toString())

      this.lightboxToggleMapBtnTarget.classList.toggle("bg-[#ffffff]", isMap)
      this.lightboxToggleMapBtnTarget.classList.toggle("text-[#0f172a]", isMap)
      this.lightboxToggleMapBtnTarget.classList.toggle("font-semibold", isMap)
      this.lightboxToggleMapBtnTarget.classList.toggle("shadow-sm", isMap)
      this.lightboxToggleMapBtnTarget.classList.toggle("text-white/80", !isMap)
      this.lightboxToggleMapBtnTarget.classList.toggle("hover:text-white", !isMap)
      this.lightboxToggleMapBtnTarget.setAttribute("aria-selected", isMap.toString())
    }

    // Update lightbox thumbs/dots
    this.lightboxDotTargets.forEach((dot, i) => {
      const active = i === normalizedIndex
      dot.classList.toggle("border-white", active)
      dot.classList.toggle("opacity-100", active)
      dot.classList.toggle("scale-105", active)
      dot.classList.toggle("border-transparent", !active)
      dot.classList.toggle("opacity-50", !active)
    })
  }

  showLightboxPhotos() {
    const target = this.photoCount > 0 ? (this.lastPhotoIndex || 0) : 0
    this.showLightboxSlide(target)
  }

  showLightboxMap() {
    if (this.canShowMap) {
      this.showLightboxSlide(this.mapIndex)
    }
  }

  initFullscreenMap() {
    if (this.fullscreenMapInitialized || !this.hasLightboxMapContainerTarget) {
      if (this.fullscreenMap) {
        setTimeout(() => {
          google.maps.event.trigger(this.fullscreenMap, "resize")
          this.fullscreenMap.setCenter({ lat: this.latValue, lng: this.lngValue })
        }, 50)
      }
      return
    }

    const lat = this.latValue
    const lng = this.lngValue
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || (lat === 0 && lng === 0)) return

    const setup = () => {
      if (this.fullscreenMapInitialized || !this.hasLightboxMapContainerTarget) return
      this.fullscreenMapInitialized = true
      this.fullscreenMap = new google.maps.Map(this.lightboxMapContainerTarget, {
        center: { lat, lng },
        zoom: 15,
        mapTypeId: google.maps.MapTypeId.ROADMAP,
        disableDefaultUI: false,
        zoomControl: true,
        streetViewControl: true,
        mapTypeControl: true,
        fullscreenControl: false
      })
      new google.maps.Marker({
        position: { lat, lng },
        map: this.fullscreenMap
      })
      setTimeout(() => {
        google.maps.event.trigger(this.fullscreenMap, "resize")
      }, 100)
    }

    if (window.google && window.google.maps) {
      setup()
    } else {
      if (this.mapCheckInterval) clearInterval(this.mapCheckInterval)
      let attempts = 0
      const maxAttempts = 50
      this.mapCheckInterval = setInterval(() => {
        attempts += 1
        if (window.google && window.google.maps) {
          clearInterval(this.mapCheckInterval)
          this.mapCheckInterval = null
          setup()
        } else if (attempts >= maxAttempts) {
          clearInterval(this.mapCheckInterval)
          this.mapCheckInterval = null
        }
      }, 150)
    }
  }

  onKeydown(e) {
    if (!this.isLightboxOpen) return
    if (e.key === "Escape") {
      this.closeLightbox()
    } else if (e.key === "ArrowRight") {
      this.lightboxNext()
    } else if (e.key === "ArrowLeft") {
      this.lightboxPrev()
    }
  }
}
