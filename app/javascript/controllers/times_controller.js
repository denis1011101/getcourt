import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["timeWrapper", "addButton"]
  static values = { max: Number, inputType: String, inputName: String }

  connect() {
    this.maxValue = this.hasMaxValue ? this.maxValue : 10
    this.inputTypeValue = this.hasInputTypeValue ? this.inputTypeValue : "time"
    this.inputNameValue = this.hasInputNameValue ? this.inputNameValue : "game[times][]"
    this.updateAddButton()
  }

  addTime(event) {
    event && event.preventDefault()
    if (this.timeWrapperTargets.length >= this.maxValue) return

    let newWrapper
    if (this.timeWrapperTargets.length > 0) {
      const firstWrapper = this.timeWrapperTargets[0]
      newWrapper = firstWrapper.cloneNode(true)
      const input = newWrapper.querySelector(`input[type="${this.inputTypeValue}"]`)
      if (input) {
        input.value = ""
        input.setAttribute("name", this.inputNameValue)
        input.removeAttribute("id")
      }
      const existingRemove = newWrapper.querySelector(".remove-time, .remove-date, .remove-item")
      if (existingRemove) existingRemove.remove()
    } else {
      newWrapper = document.createElement("div")
      newWrapper.classList.add("time-wrapper")
      newWrapper.setAttribute("data-times-target", "timeWrapper")
      const input = document.createElement("input")
      input.className = "block w-full rounded-md border border-gray-300 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-500"
      input.setAttribute("type", this.inputTypeValue)
      input.setAttribute("name", this.inputNameValue)
      newWrapper.appendChild(input)
    }

    const removeBtn = document.createElement("button")
    removeBtn.setAttribute("type", "button")
    removeBtn.textContent = "Remove"
    removeBtn.className = "remove-time mt-1 text-sm text-red-600 hover:underline"
    removeBtn.setAttribute("data-action", "click->times#removeTime")
    newWrapper.appendChild(removeBtn)

    if (this.hasAddButtonTarget) {
      this.element.insertBefore(newWrapper, this.addButtonTarget)
    } else {
      this.element.appendChild(newWrapper)
    }

    this.updateAddButton()
  }

  removeTime(event) {
    event.preventDefault()
    const wrapper = event.target.closest('.time-wrapper') || event.target.closest('[data-times-target="timeWrapper"]')
    if (!wrapper) return
    if (this.timeWrapperTargets.length <= 1) return
    wrapper.remove()
    this.updateAddButton()
  }

  updateAddButton() {
    if (!this.hasAddButtonTarget) return
    const count = this.timeWrapperTargets.length
    const labelBase = this.inputTypeValue === "date" ? "Add date" : "Add time"
    this.addButtonTarget.textContent = count >= this.maxValue ? `Max ${this.maxValue} reached` : `${labelBase} (${count}/${this.maxValue})`
    this.addButtonTarget.disabled = count >= this.maxValue
  }
}