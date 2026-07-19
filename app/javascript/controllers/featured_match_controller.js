import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["days", "time", "photos"]
  static values = {
    startsAt: String,
    startedText: String,
    daysSuffix: { type: String, default: "д" }
  }

  connect() {
    this.startsAt = new Date(this.startsAtValue)
    this.tick()
    this.timer = window.setInterval(() => this.tick(), 1000)

    if (this.hasPhotosTarget) {
      this.slideIndex = 0
      this.boundPauseSlides = () => this.pauseSlides()
      this.boundNextSlide = () => this.nextSlide({ manual: true })
      this.boundFinishAutoScroll = () => this.finishAutoScroll()
      this.photosTarget.addEventListener("scroll", this.boundPauseSlides)
      this.photosTarget.addEventListener("click", this.boundNextSlide)
      this.photosTarget.addEventListener("scrollend", this.boundFinishAutoScroll)
      this.startSlides()
    }
  }

  disconnect() {
    window.clearInterval(this.timer)
    this.stopSlides()

    if (this.hasPhotosTarget) {
      this.photosTarget.removeEventListener("scroll", this.boundPauseSlides)
      this.photosTarget.removeEventListener("click", this.boundNextSlide)
      this.photosTarget.removeEventListener("scrollend", this.boundFinishAutoScroll)
    }
  }

  tick() {
    // The countdown targets are only rendered while the match is still ahead.
    // Once it's live or finished the server renders a static status label, so
    // there's nothing left to tick.
    if (!this.hasTimeTarget) {
      window.clearInterval(this.timer)
      return
    }

    const remaining = this.startsAt - new Date()

    if (remaining <= 0) {
      this.daysTarget.textContent = ""
      this.timeTarget.textContent = this.startedTextValue
      // Keep the region's accessible name in sync with the visible "match
      // started" text; otherwise it would still announce "starts in".
      this.timeTarget.closest("[aria-label]")?.setAttribute("aria-label", this.startedTextValue)
      window.clearInterval(this.timer)
      return
    }

    const totalSeconds = Math.floor(remaining / 1000)
    const days = Math.floor(totalSeconds / 86400)
    const hours = Math.floor((totalSeconds % 86400) / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60

    this.daysTarget.textContent = days > 0 ? `${days}${this.daysSuffixValue}` : ""
    this.timeTarget.textContent = [hours, minutes, seconds]
      .map((part) => String(part).padStart(2, "0"))
      .join(":")
  }

  startSlides() {
    if (this.slideTimer || this.slides.length < 2) return

    this.slideTimer = window.setInterval(() => this.nextSlide(), 4000)
  }

  stopSlides() {
    window.clearInterval(this.slideTimer)
    window.clearTimeout(this.resumeTimeout)
    window.clearTimeout(this.autoScrollTimeout)
    this.slideTimer = null
    this.resumeTimeout = null
    this.autoScrollTimeout = null
  }

  pauseSlides() {
    if (this.isAutoScrolling) return

    this.stopSlides()
    this.resumeTimeout = window.setTimeout(() => this.startSlides(), 6000)
  }

  nextSlide({ manual = false } = {}) {
    const slides = this.slides
    if (slides.length < 2) return

    this.slideIndex = (this.computeCurrentIndex() + 1) % slides.length
    this.isAutoScrolling = !manual
    slides[this.slideIndex].scrollIntoView({ behavior: "smooth", block: "nearest", inline: "start" })
    window.clearTimeout(this.autoScrollTimeout)
    this.autoScrollTimeout = window.setTimeout(() => this.finishAutoScroll(), 1200)

    if (manual) this.pauseSlides()
  }

  computeCurrentIndex() {
    const firstSlide = this.slides[0]
    const slideWidth = firstSlide?.offsetWidth || 1
    const index = Math.round(this.photosTarget.scrollLeft / slideWidth)

    return Math.max(0, Math.min(index, this.slides.length - 1))
  }

  finishAutoScroll() {
    this.slideIndex = this.computeCurrentIndex()
    this.isAutoScrolling = false
    window.clearTimeout(this.autoScrollTimeout)
    this.autoScrollTimeout = null
  }

  get slides() {
    return this.hasPhotosTarget ? Array.from(this.photosTarget.querySelectorAll(".photo-wrap")) : []
  }
}
