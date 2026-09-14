import { Controller } from "@hotwired/stimulus"

// Поле выбора игрока с подсказками: по первым буквам имени, @ника или почты
// (users#search). Людей уже больше, чем удобно листать в select, а поле одно
// и то же и в статистике, и в предзаписи — разметка живёт в shared/user_picker.
//
// Выбор несёт hidden-поле с id; правка текста его сбрасывает — иначе к новому
// тексту прицепился бы id прошлого выбора. О выборе поле сообщает событием
// user-picker:selected, а дальше решает вызывающий: submit — отправить форму,
// в которой поле стоит, clear — очистить поле под следующего человека.
export default class extends Controller {
  static targets = ["input", "userId", "results"]
  static values = {
    url: String,
    searching: String,
    noMatches: String,
    error: String,
    submit: Boolean,
    clear: Boolean
  }

  connect() {
    this.searchTimeout = null
    this.requestId = 0
    this.activeIndex = -1
    this.onDocumentClick = (event) => {
      if (!this.element.contains(event.target)) this.hide()
    }
    document.addEventListener("click", this.onDocumentClick)
  }

  disconnect() {
    clearTimeout(this.searchTimeout)
    document.removeEventListener("click", this.onDocumentClick)
  }

  // Прежние подсказки убираем сразу, не дожидаясь ответа: иначе Enter в те
  // 200 мс до запроса брал бы подсвеченного из списка под старый текст — и в
  // предзаписи форма уходила бы не с тем человеком.
  search() {
    this.userIdTarget.value = ""
    this.startRequest()
    this.clearResults()

    const query = this.inputTarget.value.trim()
    if (query.length < 1) return

    this.searchTimeout = setTimeout(() => this.fetchUsers(query), 200)
  }

  // Фокус в поле лишь возвращает список: выбранный человек остаётся выбранным.
  reopen() {
    if (this.userIdTarget.value) return

    this.search()
  }

  // Стрелки ходят по списку, Enter берёт подсвеченного, Escape прячет список.
  // Enter в поле формы не отдаём: без выбора отправлять нечего, а с выбором
  // форму отправляет сам select.
  keydown(event) {
    const items = this.items()
    switch (event.key) {
      case "ArrowDown":
        if (!items.length) return
        event.preventDefault()
        this.highlight((this.activeIndex + 1) % items.length)
        break
      case "ArrowUp":
        if (!items.length) return
        event.preventDefault()
        this.highlight((this.activeIndex - 1 + items.length) % items.length)
        break
      case "Enter":
        event.preventDefault()
        if (items[this.activeIndex]) items[this.activeIndex].click()
        break
      case "Escape":
        this.hide()
        break
    }
  }

  // Поколение запроса растёт на каждое изменение запроса, включая уход в
  // пустую строку, — иначе подвисший ответ снова открыл бы список с людьми,
  // которых в поле уже нет.
  startRequest() {
    clearTimeout(this.searchTimeout)
    this.requestId += 1
    return this.requestId
  }

  async fetchUsers(query) {
    this.renderMessage(this.searchingValue)
    const requestId = this.requestId

    try {
      const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`, {
        headers: { Accept: "application/json" }
      })
      if (!response.ok) throw new Error(response.status)
      const users = await response.json()
      // Ответы могут прийти не в том порядке, в каком уходили запросы.
      if (requestId !== this.requestId) return
      this.renderUsers(users)
    } catch (error) {
      console.warn("User search failed:", error)
      if (requestId === this.requestId) this.renderMessage(this.errorValue)
    }
  }

  renderUsers(users) {
    if (!users.length) {
      this.renderMessage(this.noMatchesValue)
      return
    }

    this.resultsTarget.innerHTML = users
      .map(
        (user, index) => `
          <button type="button" role="option" data-action="click->user-picker#select"
                  data-index="${index}" data-id="${user.id}" data-label="${escapeAttribute(user.label)}"
                  class="block w-full border-b px-3 py-2 text-left text-sm last:border-b-0 hover:bg-gray-100 dark:border-white/10 dark:hover:bg-white/5">
            ${escapeHtml(user.label)}
          </button>`
      )
      .join("")
    this.show()
    // Первый — самое похожее совпадение: Enter берёт его без стрелок.
    this.highlight(0)
  }

  renderMessage(text) {
    this.resultsTarget.innerHTML = `<div class="px-3 py-2 text-center text-sm text-gray-500 dark:text-slate-400">${escapeHtml(text)}</div>`
    this.show()
  }

  select(event) {
    const { id, label } = event.currentTarget.dataset
    this.startRequest()
    this.userIdTarget.value = id
    this.inputTarget.value = label
    this.hide()

    this.dispatch("selected", { detail: { id, label } })

    if (this.submitValue) this.element.closest("form")?.requestSubmit()
    if (this.clearValue) this.reset()
  }

  reset() {
    this.startRequest()
    this.userIdTarget.value = ""
    this.inputTarget.value = ""
    this.clearResults()
  }

  // Спрятанный список для стрелок и Enter всё ещё список — потому чистим.
  clearResults() {
    this.resultsTarget.innerHTML = ""
    this.hide()
  }

  items() {
    return Array.from(this.resultsTarget.querySelectorAll("[role=option]"))
  }

  highlight(index) {
    const items = this.items()
    this.activeIndex = index
    items.forEach((item, position) => {
      item.classList.toggle("bg-gray-100", position === index)
      item.classList.toggle("dark:bg-white/5", position === index)
      item.setAttribute("aria-selected", position === index ? "true" : "false")
    })
  }

  show() {
    this.resultsTarget.classList.remove("hidden")
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  hide() {
    this.activeIndex = -1
    this.resultsTarget.classList.add("hidden")
    this.inputTarget.setAttribute("aria-expanded", "false")
  }
}

function escapeHtml(value) {
  const div = document.createElement("div")
  div.textContent = value == null ? "" : String(value)
  return div.innerHTML
}

function escapeAttribute(value) {
  return escapeHtml(value).replace(/"/g, "&quot;")
}
