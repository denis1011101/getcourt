import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    id: String,
    targetType: String,
    targetId: Number,
    authorId: Number,
    authorName: String,
    currentUserId: { type: String, default: "guest" },
    reportPrompt: String,
    reportSuccess: String,
    reportFailed: String,
    blockConfirm: String,
    blockSuccess: String,
    hideSuccess: String,
    undoLabel: { type: String, default: "Undo" }
  }

  connect() {
    this.handleStateChange = this.handleStateChange.bind(this)
    this.handleStorage = this.handleStorage.bind(this)

    window.addEventListener("ugc:state-changed", this.handleStateChange)
    window.addEventListener("storage", this.handleStorage)

    this.checkVisibility()
  }

  disconnect() {
    window.removeEventListener("ugc:state-changed", this.handleStateChange)
    window.removeEventListener("storage", this.handleStorage)
  }

  targetContainer() {
    if (this.element.hasAttribute("data-ugc-container")) {
      return this.element
    }
    return this.element.closest("article, [data-ugc-container]") || this.element
  }

  hideElement() {
    this.targetContainer().classList.add("hidden")
  }

  showElement() {
    this.targetContainer().classList.remove("hidden")
  }

  checkVisibility() {
    if (this.isItemHidden() || this.isAuthorBlocked()) {
      this.hideElement()
    } else {
      this.showElement()
    }
  }

  hide(event) {
    if (event) event.preventDefault()
    this.addHiddenItem(this.idValue)
    this.notifyStateChanged()

    this.showFeedback(this.hideSuccessValue || "Content hidden", () => {
      this.removeHiddenItem(this.idValue)
      this.notifyStateChanged()
    })
  }

  async blockAuthor(event) {
    if (event) event.preventDefault()
    const confirmMsg = this.blockConfirmValue || "Block this author and hide all their content?"
    if (!window.confirm(confirmMsg)) return

    this.addBlockedAuthor(this.authorIdValue)
    this.notifyStateChanged()

    try {
      const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
      await fetch("/reports", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken || "",
          "Accept": "application/json"
        },
        body: JSON.stringify({
          target_type: "User",
          target_id: this.authorIdValue,
          reason: "User blocked by viewer"
        })
      })
    } catch {
      // Non-blocking
    }

    this.showFeedback(this.blockSuccessValue || "Author blocked", () => {
      this.removeBlockedAuthor(this.authorIdValue)
      this.notifyStateChanged()
    })
  }

  async report(event) {
    if (event) event.preventDefault()
    const promptMsg = this.reportPromptValue || "Report this content? You can specify a reason (optional):"
    const reason = window.prompt(promptMsg, "")
    if (reason === null) return

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    try {
      const response = await fetch("/reports", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken || "",
          "Accept": "application/json"
        },
        body: JSON.stringify({
          target_type: this.targetTypeValue,
          target_id: this.targetIdValue,
          reason: reason
        })
      })

      const data = await response.json().catch(() => ({}))

      if (response.ok && data.ok) {
        this.addHiddenItem(this.idValue)
        this.notifyStateChanged()

        this.showFeedback(this.reportSuccessValue || "Report submitted. Content hidden.", () => {
          this.removeHiddenItem(this.idValue)
          this.notifyStateChanged()
        })
      } else {
        const errorMsg = data.error || this.reportFailedValue || "Failed to submit report. Please try again."
        window.alert(errorMsg)
      }
    } catch {
      window.alert(this.reportFailedValue || "Network error. Please try again.")
    }
  }

  notifyStateChanged() {
    this.checkVisibility()
    window.dispatchEvent(new CustomEvent("ugc:state-changed"))
  }

  handleStateChange() {
    this.checkVisibility()
  }

  handleStorage(event) {
    if (event.key === this.storageKey("blocked_authors") || event.key === this.storageKey("hidden_items")) {
      this.checkVisibility()
    }
  }

  storageKey(name) {
    const scope = this.currentUserIdValue || "guest"
    return `getcourt_${name}_${scope}`
  }

  isItemHidden() {
    if (!this.idValue) return false
    try {
      const list = JSON.parse(localStorage.getItem(this.storageKey("hidden_items")) || "[]")
      return Array.isArray(list) && list.includes(this.idValue)
    } catch {
      return false
    }
  }

  isAuthorBlocked() {
    if (!this.authorIdValue) return false
    try {
      const list = JSON.parse(localStorage.getItem(this.storageKey("blocked_authors")) || "[]")
      return Array.isArray(list) && list.map(String).includes(String(this.authorIdValue))
    } catch {
      return false
    }
  }

  addHiddenItem(id) {
    if (!id) return
    try {
      const key = this.storageKey("hidden_items")
      const list = JSON.parse(localStorage.getItem(key) || "[]")
      if (!list.includes(id)) {
        list.push(id)
        localStorage.setItem(key, JSON.stringify(list))
      }
    } catch {}
  }

  removeHiddenItem(id) {
    if (!id) return
    try {
      const key = this.storageKey("hidden_items")
      const list = JSON.parse(localStorage.getItem(key) || "[]").filter(item => item !== id)
      localStorage.setItem(key, JSON.stringify(list))
    } catch {}
  }

  addBlockedAuthor(authorId) {
    if (!authorId) return
    try {
      const key = this.storageKey("blocked_authors")
      const list = JSON.parse(localStorage.getItem(key) || "[]")
      const strId = String(authorId)
      if (!list.map(String).includes(strId)) {
        list.push(authorId)
        localStorage.setItem(key, JSON.stringify(list))
      }
    } catch {}
  }

  removeBlockedAuthor(authorId) {
    if (!authorId) return
    try {
      const key = this.storageKey("blocked_authors")
      const list = JSON.parse(localStorage.getItem(key) || "[]")
      const strId = String(authorId)
      const filtered = list.filter(item => String(item) !== strId)
      localStorage.setItem(key, JSON.stringify(filtered))
    } catch {}
  }

  showFeedback(message, undoCallback = null) {
    if (!message) return
    const toast = document.createElement("div")
    toast.className = "fixed bottom-5 right-5 z-50 flex items-center gap-3 rounded-lg bg-gray-900/95 text-white px-4 py-2.5 text-sm shadow-xl transition-opacity duration-300 pointer-events-auto"

    const textSpan = document.createElement("span")
    textSpan.textContent = message
    toast.appendChild(textSpan)

    if (undoCallback) {
      const undoBtn = document.createElement("button")
      undoBtn.type = "button"
      undoBtn.className = "ml-2 rounded px-2 py-0.5 text-xs font-semibold text-indigo-300 hover:text-indigo-200 hover:bg-white/10 underline cursor-pointer"
      undoBtn.textContent = this.undoLabelValue || "Undo"
      undoBtn.onclick = () => {
        undoCallback()
        toast.remove()
      }
      toast.appendChild(undoBtn)
    }

    document.body.appendChild(toast)
    setTimeout(() => {
      toast.style.opacity = "0"
      setTimeout(() => toast.remove(), 300)
    }, undoCallback ? 5000 : 3000)
  }
}
