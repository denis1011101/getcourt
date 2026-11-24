import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "input",
    "dropzone",
    "emptyState",
    "previewContainer",
    "previewImage",
    "fileName",
    "fileSize",
    "errorMessage",
    "submitBtn"
  ]

  connect() {
    this.objectUrl = null
    this.errorTimeout = null
    if (this.hasInputTarget && this.inputTarget.files && this.inputTarget.files.length > 0) {
      this.handleFile(this.inputTarget.files[0])
    } else {
      this.updateSubmitState()
    }
  }

  disconnect() {
    this.revokeCurrentUrl()
    if (this.errorTimeout) {
      clearTimeout(this.errorTimeout)
      this.errorTimeout = null
    }
  }

  browse(event) {
    if (event) {
      if (event.target === this.inputTarget || event.target.closest("button")) return
      event.stopPropagation()
    }
    if (this.hasInputTarget) {
      this.inputTarget.click()
    }
  }

  submitOrBrowse(event) {
    const hasFile = Boolean(this.hasInputTarget && this.inputTarget.files && this.inputTarget.files.length > 0)
    if (!hasFile) {
      event.preventDefault()
      event.stopPropagation()
      this.browse()
    }
  }

  onDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "copy"
    if (this.hasDropzoneTarget) {
      this.dropzoneTarget.classList.add(
        "border-indigo-500",
        "bg-indigo-50/50",
        "dark:border-indigo-400",
        "dark:bg-indigo-500/15"
      )
    }
  }

  onDragLeave(event) {
    event.preventDefault()
    if (event.relatedTarget && this.hasDropzoneTarget && this.dropzoneTarget.contains(event.relatedTarget)) {
      return
    }
    if (this.hasDropzoneTarget) {
      this.dropzoneTarget.classList.remove(
        "border-indigo-500",
        "bg-indigo-50/50",
        "dark:border-indigo-400",
        "dark:bg-indigo-500/15"
      )
    }
  }

  onDrop(event) {
    event.preventDefault()
    this.onDragLeave(event)

    const files = event.dataTransfer?.files
    if (!files || files.length === 0) return

    const file = files[0]
    if (!this.isValidImage(file)) {
      this.showError("Please select a JPG, PNG, or WebP image.")
      return
    }
    if (file.size > 5 * 1024 * 1024) {
      this.showError("Photo must be less than 5 MB.")
      return
    }

    try {
      const dt = new DataTransfer()
      dt.items.add(file)
      this.inputTarget.files = dt.files
    } catch {
      this.inputTarget.files = files
    }

    this.handleFile(file)
  }

  onFileChange() {
    const files = this.inputTarget.files
    if (files && files.length > 0) {
      const file = files[0]
      if (!this.isValidImage(file)) {
        this.clear()
        this.showError("Please select a JPG, PNG, or WebP image.")
        return
      }
      if (file.size > 5 * 1024 * 1024) {
        this.clear()
        this.showError("Photo must be less than 5 MB.")
        return
      }
      this.handleFile(file)
    } else {
      this.clear()
    }
  }

  isValidImage(file) {
    if (!file) return false
    const validTypes = ["image/jpeg", "image/png", "image/webp"]
    if (file.type) return validTypes.includes(file.type)
    if (file.name) return /\.(jpe?g|png|webp)$/i.test(file.name)
    return false
  }

  showError(message) {
    if (this.errorTimeout) {
      clearTimeout(this.errorTimeout)
      this.errorTimeout = null
    }
    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.textContent = message
      this.errorMessageTarget.classList.remove("hidden")
      this.errorTimeout = setTimeout(() => {
        if (this.hasErrorMessageTarget) {
          this.errorMessageTarget.classList.add("hidden")
        }
        this.errorTimeout = null
      }, 4000)
    } else {
      alert(message)
    }
  }

  handleFile(file) {
    this.revokeCurrentUrl()
    this.objectUrl = URL.createObjectURL(file)

    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.classList.add("hidden")
    }

    if (this.hasPreviewImageTarget) {
      this.previewImageTarget.src = this.objectUrl
    }
    if (this.hasFileNameTarget) {
      this.fileNameTarget.textContent = file.name
    }
    if (this.hasFileSizeTarget) {
      this.fileSizeTarget.textContent = this.formatBytes(file.size)
    }

    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.add("hidden")
    }
    if (this.hasPreviewContainerTarget) {
      this.previewContainerTarget.classList.remove("hidden")
    }

    this.updateSubmitState()
  }

  clear(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }

    this.revokeCurrentUrl()

    if (this.hasInputTarget) {
      this.inputTarget.value = ""
    }
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.remove("hidden")
    }
    if (this.hasPreviewContainerTarget) {
      this.previewContainerTarget.classList.add("hidden")
    }
    if (this.hasPreviewImageTarget) {
      this.previewImageTarget.removeAttribute("src")
    }
    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.classList.add("hidden")
    }

    this.updateSubmitState()
  }

  revokeCurrentUrl() {
    if (this.objectUrl) {
      URL.revokeObjectURL(this.objectUrl)
      this.objectUrl = null
    }
  }

  updateSubmitState() {
    if (!this.hasSubmitBtnTarget) return
    const hasFile = Boolean(this.hasInputTarget && this.inputTarget.files && this.inputTarget.files.length > 0)
    if (hasFile) {
      this.submitBtnTarget.classList.remove("opacity-80")
    } else {
      this.submitBtnTarget.classList.add("opacity-80")
    }
  }

  formatBytes(bytes) {
    if (!bytes || bytes === 0) return "0 B"
    const k = 1024
    const sizes = ["B", "KB", "MB", "GB"]
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    const formatted = parseFloat((bytes / Math.pow(k, i)).toFixed(1))
    return `${formatted} ${sizes[i]}`
  }
}
