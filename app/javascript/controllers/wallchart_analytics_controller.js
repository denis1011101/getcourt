import { Controller } from "@hotwired/stimulus"
import ahoy from "ahoy"

// Tracks Wallchart '26 campaign events with Ahoy.
//
// - When a `view-event` is set, fires once via IntersectionObserver as soon as
//   at least 50% of the element is visible (a real impression, not a render).
// - When a `click-event` is set, fires on click (wire up with
//   data-action="click->wallchart-analytics#click").
export default class extends Controller {
  static values = {
    campaign: String,
    eventSlug: String,
    locale: String,
    viewEvent: String,
    clickEvent: String
  }

  connect() {
    if (!this.hasViewEventValue) return

    this.observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting && entry.intersectionRatio >= 0.5) {
            this.track(this.viewEventValue)
            this.observer.disconnect()
            break
          }
        }
      },
      { threshold: [0.5] }
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  click() {
    if (this.hasClickEventValue) this.track(this.clickEventValue)
  }

  track(name) {
    ahoy.track(name, {
      campaign: this.campaignValue,
      event_slug: this.eventSlugValue,
      locale: this.localeValue
    })
  }
}
