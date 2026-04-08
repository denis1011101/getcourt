import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "input", "messages", "button", "spinner", "quickReplies"]
  static values = { url: String, open: { type: Boolean, default: false } }

  toggle() {
    this.openValue = !this.openValue
  }

  openValueChanged() {
    this.panelTarget.classList.toggle("hidden", !this.openValue)
    if (this.openValue) {
      this.inputTarget.focus()
      this.scrollToBottom()
    }
  }

  close() {
    this.openValue = false
  }

  async send(event) {
    event.preventDefault()
    const message = this.inputTarget.value.trim()
    if (!message) return

    this.inputTarget.value = ""
    this.inputTarget.disabled = true
    this.spinnerTarget.classList.remove("hidden")
    this.appendMessage("user", message)

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        body: JSON.stringify({ message })
      })
      const data = await response.json()
      this.appendMessage("assistant", data.reply || data.error || "Error", data.reply_html)
    } catch {
      this.appendMessage("assistant", "Connection error. Try again.")
    } finally {
      this.inputTarget.disabled = false
      this.spinnerTarget.classList.add("hidden")
      this.inputTarget.focus()
    }
  }

  quickSend(event) {
    const message = event.params.message
    if (!message) return
    if (this.hasQuickRepliesTarget) {
      this.quickRepliesTarget.classList.add("hidden")
    }
    this.inputTarget.value = message
    this.inputTarget.focus()
    if (event.params.mode === "insert") return
    this.send(event)
  }

  handleKey(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.send(event)
    }
  }

  appendMessage(role, text, html = null) {
    const isUser = role === "user"
    const div = document.createElement("div")
    div.className = isUser
      ? "flex justify-end"
      : "flex justify-start"

    const bubble = document.createElement("div")
    bubble.className = isUser
      ? "max-w-[80%] rounded-2xl rounded-br-sm bg-indigo-600 text-white px-3 py-2 text-sm whitespace-pre-wrap"
      : "max-w-[80%] rounded-2xl rounded-bl-sm bg-gray-100 dark:bg-slate-700 text-gray-900 dark:text-slate-100 px-3 py-2 text-sm whitespace-pre-wrap"

    if (!isUser && html) {
      bubble.innerHTML = html
    } else {
      bubble.textContent = text
    }
    div.appendChild(bubble)
    this.messagesTarget.appendChild(div)
    this.scrollToBottom()
  }

  scrollToBottom() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }
}
