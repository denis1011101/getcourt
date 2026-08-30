import { Controller } from "@hotwired/stimulus"

// Координатная сетка совпадает с TrainingBlock::Diagram и с viewBox разметки
// корта: 100 единиц в ширину, 200 в длину. Лимиты дублируют серверные — не
// потому, что им верят, а чтобы редактор не давал нарисовать то, что сервер
// потом молча срежет.
const WIDTH = 100
const HEIGHT = 200
const MAX_FRAMES = 8
const MAX_ITEMS = 16
const MAX_ARROWS = 20
const MIN_ARROW_LENGTH = 3
const UNDO_LIMIT = 20
const SVG_NS = "http://www.w3.org/2000/svg"

const ITEM_TOOLS = ["player", "opponent", "coach", "ball", "cone"]
// Инструмент «стрелка бега» и «стрелка мяча» кладут разный kind в одну и ту же фигуру.
const ARROW_TOOLS = { run: "run", ball_path: "ball" }

const ITEM_COLORS = {
  player: "#4F46E5",
  opponent: "#E11D48",
  coach: "#0F172A",
  ball: "#FACC15",
  cone: "#F97316"
}

export default class extends Controller {
  static targets = ["svg", "layer", "input", "tabs", "frameTitle", "tool"]
  static values = { diagram: Object, readonly: Boolean }

  connect() {
    this.frames = this.#framesFrom(this.diagramValue)
    this.frameIndex = 0
    this.tool = "select"
    this.selected = null
    this.dragging = null
    this.draft = null
    this.undoStack = []
    this.render()
  }

  // --- инструменты ---------------------------------------------------------

  selectTool(event) {
    this.tool = event.currentTarget.dataset.tool
    this.selected = null
    this.render()
  }

  // --- рисование -----------------------------------------------------------

  start(event) {
    if (this.readonlyValue) return
    event.preventDefault()
    const point = this.#point(event)

    if (this.tool === "select") {
      const index = this.#itemIndexAt(event.target)
      this.selected = index
      if (index !== null) {
        this.#pushUndo()
        this.dragging = index
        this.#capture(event)
      }
      this.render()
      return
    }

    if (ITEM_TOOLS.includes(this.tool)) {
      if (this.frame.items.length >= MAX_ITEMS) return

      this.#pushUndo()
      this.frame.items.push({
        kind: this.tool,
        label: this.#nextLabel(this.tool),
        x: point.x,
        y: point.y
      })
      this.render()
      return
    }

    const kind = ARROW_TOOLS[this.tool]
    if (kind && this.frame.arrows.length < MAX_ARROWS) {
      this.#pushUndo()
      this.draft = { kind, x1: point.x, y1: point.y, x2: point.x, y2: point.y }
      this.#capture(event)
      this.render()
    }
  }

  move(event) {
    if (this.dragging === null && !this.draft) return
    event.preventDefault()
    const point = this.#point(event)

    if (this.draft) {
      this.draft.x2 = point.x
      this.draft.y2 = point.y
    } else {
      const item = this.frame.items[this.dragging]
      item.x = point.x
      item.y = point.y
    }

    this.render()
  }

  finish(event) {
    if (this.draft) {
      const { x1, y1, x2, y2 } = this.draft
      if (Math.hypot(x2 - x1, y2 - y1) >= MIN_ARROW_LENGTH) {
        this.frame.arrows.push(this.draft)
      } else {
        // Тычок вместо жеста: ни стрелки, ни шага в истории отмены.
        this.undoStack.pop()
      }
      this.draft = null
    }

    this.dragging = null
    this.#release(event)
    this.render()
  }

  // --- правки --------------------------------------------------------------

  deleteSelected() {
    if (this.selected === null) return

    this.#pushUndo()
    this.frame.items.splice(this.selected, 1)
    this.selected = null
    this.render()
  }

  clearFrame() {
    this.#pushUndo()
    this.frames[this.frameIndex] = this.#blankFrame(this.frame.title)
    this.selected = null
    this.render()
  }

  undo() {
    const snapshot = this.undoStack.pop()
    if (!snapshot) return

    this.frames = JSON.parse(snapshot)
    this.frameIndex = Math.min(this.frameIndex, this.frames.length - 1)
    this.selected = null
    this.render()
  }

  // --- кадры ---------------------------------------------------------------

  selectFrame(event) {
    this.frameIndex = Number(event.currentTarget.dataset.frameIndex)
    this.selected = null
    this.render()
  }

  addFrame() {
    if (this.frames.length >= MAX_FRAMES) return

    this.#pushUndo()
    this.frames.push(this.#blankFrame())
    this.frameIndex = this.frames.length - 1
    this.selected = null
    this.render()
  }

  // Фазы упражнения отличаются одним-двумя шагами, поэтому следующий кадр почти
  // всегда начинается с копии предыдущего.
  duplicateFrame() {
    if (this.frames.length >= MAX_FRAMES) return

    this.#pushUndo()
    this.frames.splice(this.frameIndex + 1, 0, JSON.parse(JSON.stringify(this.frame)))
    this.frameIndex += 1
    this.selected = null
    this.render()
  }

  deleteFrame() {
    this.#pushUndo()
    this.frames.splice(this.frameIndex, 1)
    if (this.frames.length === 0) this.frames.push(this.#blankFrame())
    this.frameIndex = Math.min(this.frameIndex, this.frames.length - 1)
    this.selected = null
    this.render()
  }

  updateFrameTitle(event) {
    this.frame.title = event.currentTarget.value
    this.#save()
  }

  // --- отрисовка -----------------------------------------------------------

  render() {
    this.#renderLayer()
    this.#renderTabs()
    this.#renderTools()

    if (this.hasFrameTitleTarget && document.activeElement !== this.frameTitleTarget) {
      this.frameTitleTarget.value = this.frame.title || ""
    }

    this.#save()
  }

  get frame() {
    return this.frames[this.frameIndex]
  }

  #renderLayer() {
    const layer = this.layerTarget
    layer.replaceChildren()

    this.frame.arrows.forEach((arrow) => layer.appendChild(this.#arrowNode(arrow)))
    if (this.draft) layer.appendChild(this.#arrowNode(this.draft, true))
    this.frame.items.forEach((item, index) => layer.appendChild(this.#itemNode(item, index)))
  }

  #renderTabs() {
    if (!this.hasTabsTarget) return

    this.tabsTarget.replaceChildren()
    this.frames.forEach((frame, index) => {
      const button = document.createElement("button")
      button.type = "button"
      button.dataset.frameIndex = index
      button.dataset.action = "court-diagram#selectFrame"
      button.textContent = frame.title?.trim() || String(index + 1)
      button.className =
        index === this.frameIndex
          ? "rounded bg-indigo-600 px-2 py-1 text-xs text-white"
          : "rounded border border-gray-300 px-2 py-1 text-xs text-gray-600 dark:border-white/15 dark:text-slate-300"
      this.tabsTarget.appendChild(button)
    })
  }

  #renderTools() {
    this.toolTargets.forEach((button) => {
      const active = button.dataset.tool === this.tool
      button.classList.toggle("bg-indigo-600", active)
      button.classList.toggle("text-white", active)
      button.classList.toggle("border-indigo-600", active)
      button.setAttribute("aria-pressed", active)
    })
  }

  #itemNode(item, index) {
    const group = document.createElementNS(SVG_NS, "g")
    group.dataset.itemIndex = index
    group.setAttribute("transform", `translate(${item.x} ${item.y})`)
    group.style.cursor = this.readonlyValue ? "default" : "move"

    const color = ITEM_COLORS[item.kind] || ITEM_COLORS.player
    const shape = this.#shapeNode(item.kind)
    shape.setAttribute("fill", color)
    if (index === this.selected) {
      shape.setAttribute("stroke", "#FFFFFF")
      shape.setAttribute("stroke-width", "1.2")
    }
    group.appendChild(shape)

    if (item.label) {
      const text = document.createElementNS(SVG_NS, "text")
      text.setAttribute("text-anchor", "middle")
      text.setAttribute("dominant-baseline", "central")
      text.setAttribute("font-size", "4.5")
      text.setAttribute("fill", "#FFFFFF")
      // Иначе подпись перехватывает pointerdown и фигура перестаёт таскаться.
      text.setAttribute("pointer-events", "none")
      text.textContent = item.label
      group.appendChild(text)
    }

    return group
  }

  #shapeNode(kind) {
    if (kind === "coach") {
      const rect = document.createElementNS(SVG_NS, "rect")
      rect.setAttribute("x", "-4.5")
      rect.setAttribute("y", "-4.5")
      rect.setAttribute("width", "9")
      rect.setAttribute("height", "9")
      rect.setAttribute("rx", "1.5")
      return rect
    }

    if (kind === "cone") {
      const polygon = document.createElementNS(SVG_NS, "polygon")
      polygon.setAttribute("points", "0,-4.5 4,4 -4,4")
      return polygon
    }

    const circle = document.createElementNS(SVG_NS, "circle")
    circle.setAttribute("r", kind === "ball" ? "2.4" : "4.5")
    return circle
  }

  #arrowNode(arrow, draft = false) {
    const group = document.createElementNS(SVG_NS, "g")
    group.setAttribute("stroke", "currentColor")
    group.setAttribute("fill", "currentColor")
    group.setAttribute("pointer-events", "none")
    if (draft) group.setAttribute("opacity", "0.6")

    const line = document.createElementNS(SVG_NS, "line")
    line.setAttribute("x1", arrow.x1)
    line.setAttribute("y1", arrow.y1)
    line.setAttribute("x2", arrow.x2)
    line.setAttribute("y2", arrow.y2)
    line.setAttribute("stroke-width", "1.2")
    line.setAttribute("stroke-linecap", "round")
    // Пунктир — полёт мяча, сплошная — перемещение игрока: так эти стрелки
    // рисуют в тренерских конспектах.
    if (arrow.kind === "ball") line.setAttribute("stroke-dasharray", "4 3")
    group.appendChild(line)

    // Наконечник считаем сами, а не через <marker>: маркеру нужен уникальный id,
    // а редакторов на странице столько же, сколько блоков в библиотеке.
    const angle = Math.atan2(arrow.y2 - arrow.y1, arrow.x2 - arrow.x1)
    const size = 3.2
    const points = [
      [ arrow.x2, arrow.y2 ],
      [ arrow.x2 - size * Math.cos(angle - Math.PI / 7), arrow.y2 - size * Math.sin(angle - Math.PI / 7) ],
      [ arrow.x2 - size * Math.cos(angle + Math.PI / 7), arrow.y2 - size * Math.sin(angle + Math.PI / 7) ]
    ]
    const head = document.createElementNS(SVG_NS, "polygon")
    head.setAttribute("points", points.map(([ x, y ]) => `${x},${y}`).join(" "))
    head.setAttribute("stroke", "none")
    group.appendChild(head)

    return group
  }

  // --- служебное -----------------------------------------------------------

  #framesFrom(value) {
    const raw = Array.isArray(value?.frames) ? value.frames : []
    const frames = raw.map((frame) => ({
      title: typeof frame?.title === "string" ? frame.title : "",
      items: Array.isArray(frame?.items) ? frame.items : [],
      arrows: Array.isArray(frame?.arrows) ? frame.arrows : []
    }))

    return frames.length > 0 ? frames : [ this.#blankFrame() ]
  }

  #blankFrame(title = "") {
    return { title, items: [], arrows: [] }
  }

  // Подписи раздаём по порядку: игроки буквами, соперники цифрами. Остальные
  // фигуры узнаются по форме, подпись им только мешает.
  #nextLabel(kind) {
    const taken = this.frame.items.filter((item) => item.kind === kind).length
    if (kind === "player") return String.fromCharCode(65 + (taken % 26))
    if (kind === "opponent") return String((taken % 9) + 1)
    return ""
  }

  // Экран → координаты viewBox. Считаем на каждое событие, а не кэшируем: холст
  // живёт внутри <details> и до раскрытия у него вообще нет размеров.
  #point(event) {
    const matrix = this.svgTarget.getScreenCTM()
    if (!matrix) return { x: 0, y: 0 }

    const point = new DOMPoint(event.clientX, event.clientY).matrixTransform(matrix.inverse())
    return {
      x: Math.round(Math.min(Math.max(point.x, 0), WIDTH) * 100) / 100,
      y: Math.round(Math.min(Math.max(point.y, 0), HEIGHT) * 100) / 100
    }
  }

  #itemIndexAt(target) {
    const node = target.closest?.("[data-item-index]")
    return node ? Number(node.dataset.itemIndex) : null
  }

  #capture(event) {
    this.svgTarget.setPointerCapture?.(event.pointerId)
  }

  #release(event) {
    if (this.svgTarget.hasPointerCapture?.(event.pointerId)) {
      this.svgTarget.releasePointerCapture(event.pointerId)
    }
  }

  #pushUndo() {
    this.undoStack.push(JSON.stringify(this.frames))
    if (this.undoStack.length > UNDO_LIMIT) this.undoStack.shift()
  }

  #save() {
    if (this.readonlyValue || !this.hasInputTarget) return

    this.inputTarget.value = JSON.stringify({ frames: this.frames })
  }
}
