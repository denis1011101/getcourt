import { Controller } from "@hotwired/stimulus"

// «−» и «+» вокруг числового поля: кому-то удобнее натыкать счёт, чем
// вызывать клавиатуру. Пустое поле считается нулём, ниже нуля не уходим.
export default class extends Controller {
  static targets = ["input"]

  increment() {
    this.change(1)
  }

  decrement() {
    this.change(-1)
  }

  change(delta) {
    const current = parseInt(this.inputTarget.value, 10) || 0
    this.inputTarget.value = Math.max(0, current + delta)
  }
}
