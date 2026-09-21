import { Controller } from "@hotwired/stimulus"

// Календарь игры: вместо нативного поля даты показывает месяц, в котором
// отмечают все занятия сразу — хоть «пн и чт на этой неделе, пн и ср на
// следующей». Отмеченные даты и есть расписание; галки повтора только
// продолжают его за последней отметкой — каждую неделю по тем же дням недели
// или каждый месяц по тем же числам.
export default class extends Controller {
  static targets = ["input", "dateField", "calendar", "title", "grid", "mode"]
  static values = {
    selected: Array,
    weekdays: Array,
    months: Array,
    modeDates: String,
    modeWeekly: String,
    modeMonthly: String,
    modeFinite: String,
    min: String,
    max: String
  }

  connect() {
    this.selected = new Set(this.selectedValue.filter(Boolean))
    this.month = this.startOfMonth(this.earliest() || this.today())
    this.repeatInputs = [ document.getElementById("game_recurring"), document.getElementById("game_recurring_monthly") ].filter(Boolean)
    this.repeatListener = (event) => this.repeatChanged(event)
    this.repeatInputs.forEach((input) => input.addEventListener("change", this.repeatListener))

    // Нативное поле остаётся в форме и продолжает возить дату на сервер, но с
    // включённым JS его место занимает календарь.
    this.dateFieldTarget.classList.add("hidden")
    this.calendarTarget.classList.remove("hidden")
    this.render()
  }

  disconnect() {
    this.repeatInputs.forEach((input) => input.removeEventListener("change", this.repeatListener))
  }

  previousMonth() {
    this.month = new Date(this.month.getFullYear(), this.month.getMonth() - 1, 1)
    this.render()
  }

  nextMonth() {
    this.month = new Date(this.month.getFullYear(), this.month.getMonth() + 1, 1)
    this.render()
  }

  // Отметка — это занятие: клик добавляет день и снимает его обратно. Последнюю
  // отметку снять нельзя, иначе у игры не осталось бы даты.
  toggle(event) {
    const iso = event.currentTarget.dataset.date

    if (!this.selected.has(iso)) {
      this.selected.add(iso)
    } else if (this.selected.size > 1) {
      this.selected.delete(iso)
    }

    this.render()
  }

  // Еженедельно и ежемесячно — это два разных продолжения одного расписания,
  // вместе они читались бы как загадка.
  repeatChanged(event) {
    if (event.target.checked) {
      this.repeatInputs.filter((input) => input !== event.target).forEach((input) => { input.checked = false })
    }

    this.render()
  }

  get weekly() {
    return Boolean(document.getElementById("game_recurring")?.checked)
  }

  get monthly() {
    return Boolean(document.getElementById("game_recurring_monthly")?.checked)
  }

  render() {
    this.titleTarget.textContent = `${this.monthsValue[this.month.getMonth()]} ${this.month.getFullYear()}`
    this.gridTarget.replaceChildren(...this.weekdayHeaders(), ...this.dayCells())

    const dates = this.sortedDates()
    this.inputTarget.value = dates.map((date) => this.iso(date)).join(",")
    this.dateFieldTarget.value = dates.length ? this.iso(dates[0]) : ""
    this.renderMode(dates)
    this.syncPrebooking(dates)
  }

  // Строка под сеткой пересказывает расписание словами: сколько занятий
  // отмечено и что будет после последнего.
  renderMode(dates) {
    const parts = [ this.modeDatesValue.replace("%{count}", dates.length) ]

    if (this.weekly) {
      parts.push(this.modeWeeklyValue.replace("%{days}", this.weekdayNames(dates)))
    } else if (this.monthly) {
      parts.push(this.modeMonthlyValue.replace("%{days}", this.monthDayNames(dates)))
    } else {
      parts.push(this.modeFiniteValue)
    }

    this.modeTarget.textContent = parts.join(" · ")
  }

  // Предзапись и всё, что происходит после занятия, живёт у серии: одна дата
  // без повтора — обычная разовая игра.
  syncPrebooking(dates) {
    const series = dates.length > 1 || this.weekly || this.monthly
    const seriesOnly = [ "game_prebooking_enabled", "game_reset_lineup", "game_release_court_on_reset" ]

    seriesOnly.forEach((id) => {
      const checkbox = document.getElementById(id)
      if (!checkbox) return

      checkbox.disabled = !series
      // Очистку состава не снимаем: у серии она включена по умолчанию, и
      // щелчок повтором туда-обратно не должен её терять.
      if (!series && id !== "game_reset_lineup") checkbox.checked = false
    })
  }

  weekdayNames(dates) {
    return [ ...new Set(dates.map((date) => date.getDay())) ]
      .sort((left, right) => ((left + 6) % 7) - ((right + 6) % 7))
      .map((wday) => this.weekdaysValue[wday])
      .join(", ")
  }

  monthDayNames(dates) {
    return [ ...new Set(dates.map((date) => date.getDate())) ].sort((left, right) => left - right).join(", ")
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
    // cursor-pointer явно: у кнопок в Tailwind v4 курсор по умолчанию обычный.
    const base = "flex min-h-11 cursor-pointer items-center justify-center rounded-md text-sm leading-tight transition disabled:cursor-not-allowed sm:min-h-12"

    if (this.selected.has(iso)) {
      return `${base} bg-indigo-600 font-semibold text-white hover:bg-indigo-700`
    }
    if (this.repeats(date)) {
      // Тень повтора: в этот день игра тоже состоится, но отметки на нём нет —
      // он приходит из галки, а не из календаря.
      return `${base} bg-indigo-100 text-indigo-800 hover:bg-indigo-200 dark:bg-indigo-500/30 dark:text-indigo-50`
    }

    return `${base} bg-gray-50 text-gray-700 hover:bg-gray-100 disabled:opacity-40 disabled:hover:bg-gray-50 dark:bg-white/5 dark:text-slate-300 dark:hover:bg-white/10`
  }

  // Продолжение расписания начинается за последней отметкой — до неё занятия
  // ровно те, что отмечены руками.
  repeats(date) {
    const dates = this.sortedDates()
    const last = dates[dates.length - 1]
    if (!last || date <= last) return false

    if (this.weekly) return dates.some((selected) => selected.getDay() === date.getDay())
    if (this.monthly) return dates.some((selected) => selected.getDate() === date.getDate())

    return false
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
