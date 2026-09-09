import { Controller } from "@hotwired/stimulus"

// Календарь игры: вместо нативного поля даты показывает месяц, в котором можно
// отметить несколько дней. Игра при этом остаётся одной — сервер берёт самую
// раннюю отметку как дату, а дни недели всех отметок становятся расписанием
// повторов. Пока «повторять еженедельно» не отмечено, день выбирается один:
// иначе клик по соседней дате молча превращал бы разовую игру в серию.
export default class extends Controller {
  static targets = ["input", "dateField", "calendar", "title", "grid"]
  static values = {
    selected: Array,
    weekdays: Array,
    months: Array,
    min: String,
    max: String
  }

  connect() {
    this.selected = new Set(this.selectedValue.filter(Boolean))
    this.month = this.startOfMonth(this.earliest() || this.today())
    this.recurringInput = document.getElementById("game_recurring")
    this.recurringListener = () => this.recurringChanged()
    this.recurringInput?.addEventListener("change", this.recurringListener)

    // Нативное поле остаётся в форме и продолжает возить дату на сервер, но с
    // включённым JS его место занимает календарь.
    this.dateFieldTarget.classList.add("hidden")
    this.calendarTarget.classList.remove("hidden")
    this.render()
  }

  disconnect() {
    this.recurringInput?.removeEventListener("change", this.recurringListener)
  }

  previousMonth() {
    this.month = new Date(this.month.getFullYear(), this.month.getMonth() - 1, 1)
    this.render()
  }

  nextMonth() {
    this.month = new Date(this.month.getFullYear(), this.month.getMonth() + 1, 1)
    this.render()
  }

  toggle(event) {
    const iso = event.currentTarget.dataset.date

    if (!this.recurring) {
      this.selected = new Set([iso])
    } else if (!this.selected.has(iso)) {
      this.selected.add(iso)
    } else if (this.selected.size > 1) {
      this.selected.delete(iso)
    }

    this.render()
  }

  // Снятая галочка повтора оставляет одну дату: расписания у разовой игры нет.
  recurringChanged() {
    if (!this.recurring && this.selected.size > 1) {
      this.selected = new Set([this.iso(this.earliest())])
    }

    this.render()
  }

  get recurring() {
    return Boolean(this.recurringInput?.checked)
  }

  render() {
    this.titleTarget.textContent = `${this.monthsValue[this.month.getMonth()]} ${this.month.getFullYear()}`
    this.gridTarget.replaceChildren(...this.weekdayHeaders(), ...this.dayCells())

    const dates = this.sortedDates()
    this.inputTarget.value = dates.map((date) => this.iso(date)).join(",")
    this.dateFieldTarget.value = dates.length ? this.iso(dates[0]) : ""
  }

  weekdayHeaders() {
    // Неделя начинается с понедельника, а подписи лежат в порядке Date#getDay.
    return [1, 2, 3, 4, 5, 6, 0].map((wday) => {
      const cell = document.createElement("span")
      cell.className = "pb-1 text-center text-[10px] uppercase tracking-wide text-gray-400 dark:text-slate-500"
      cell.textContent = this.weekdaysValue[wday]
      return cell
    })
  }

  dayCells() {
    const cells = []
    const day = this.startOfMonth(this.month)
    day.setDate(day.getDate() - (day.getDay() + 6) % 7)

    while (cells.length < 42) {
      cells.push(this.dayCell(new Date(day)))
      day.setDate(day.getDate() + 1)
    }

    return cells
  }

  dayCell(date) {
    const iso = this.iso(date)
    const cell = document.createElement("button")
    cell.type = "button"
    cell.dataset.date = iso
    cell.textContent = date.getDate()
    cell.disabled = this.outOfRange(iso)
    cell.className = this.cellClasses(date, iso)

    if (!cell.disabled) cell.dataset.action = "click->date-picker#toggle"
    if (date.getMonth() !== this.month.getMonth()) cell.classList.add("opacity-40")
    if (iso === this.iso(this.today())) cell.classList.add("ring-2", "ring-indigo-400", "dark:ring-indigo-300")

    return cell
  }

  cellClasses(date, iso) {
    const base = "flex min-h-11 items-center justify-center rounded-md text-sm leading-tight transition sm:min-h-12"

    if (this.selected.has(iso)) {
      return `${base} bg-indigo-600 font-semibold text-white hover:bg-indigo-700`
    }
    if (this.repeats(date)) {
      // Тень повтора: в этот день игра тоже состоится, но отметку с неё не снять
      // — снимают её с самого дня недели, то есть с первой, отмеченной даты.
      return `${base} bg-indigo-100 text-indigo-800 hover:bg-indigo-200 dark:bg-indigo-500/30 dark:text-indigo-50`
    }

    return `${base} bg-gray-50 text-gray-700 hover:bg-gray-100 disabled:opacity-40 disabled:hover:bg-gray-50 dark:bg-white/5 dark:text-slate-300 dark:hover:bg-white/10`
  }

  repeats(date) {
    if (!this.recurring) return false

    const first = this.earliest()
    return Boolean(first) && date > first && this.sortedDates().some((selected) => selected.getDay() === date.getDay())
  }

  outOfRange(iso) {
    return (this.minValue && iso < this.minValue) || (this.maxValue && iso > this.maxValue)
  }

  sortedDates() {
    return [...this.selected].sort().map((iso) => this.parse(iso))
  }

  earliest() {
    return this.sortedDates()[0]
  }

  // Даты живут в локальном времени: iso8601 через toISOString сдвинул бы день
  // на часовых поясах восточнее Гринвича.
  iso(date) {
    if (!date) return ""

    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`
  }

  parse(iso) {
    const [year, month, day] = iso.split("-").map(Number)
    return new Date(year, month - 1, day)
  }

  startOfMonth(date) {
    return new Date(date.getFullYear(), date.getMonth(), 1)
  }

  today() {
    const now = new Date()
    return new Date(now.getFullYear(), now.getMonth(), now.getDate())
  }
}
