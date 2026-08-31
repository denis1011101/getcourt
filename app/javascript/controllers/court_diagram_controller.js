import { Controller } from "@hotwired/stimulus"
import { openEditor } from "court_diagram/runtime"

// Здесь остались только события и отрисовка. Кадры, фигуры, стрелки, подписи,
// отмена и лимиты живут в TrainingBlock::Diagram::Editor и крутятся в ruby.wasm:
// правила разбора схемы должны быть одни и те же в браузере и на сервере, а
// продублированные константы расходятся ровно в тот день, когда их поправят с
// одной стороны.
const SVG_NS = "http://www.w3.org/2000/svg"

const ITEM_COLORS = {
  player: "#4F46E5",
  opponent: "#E11D48",
  coach: "#0F172A",
  ball: "#FACC15",
  cone: "#F97316"
}

export default class extends Controller {
  static targets = [ "svg", "layer", "input", "tabs", "frameTitle", "tool", "status" ]
  static values = { diagram: Object, readonly: Boolean, source: String }

  connect() {
    this.send = null
    this.state = this.#serverState()
    this.render()

    // Просмотр обходится без Ruby: схема уже посчитана сервером, а в плане игры
    // таких схем пять штук — тащить ради них рантайм незачем.
    if (!this.readonlyValue) this.#boot()
  }

  disconnect() {
    // Иначе редакторы копятся в общем VM: Turbo перерисовывает библиотеку на
    // каждое сохранение блока.
    try {
      this.send?.("close")
    } catch (error) {
      console.error("court diagram", error)
    }

    this.send = null
  }

  async #boot() {
    this.#busy(true)

    try {
      const { send, state } = await openEditor(this.sourceValue, this.diagramValue)

      // Пока грузился рантайм, блок мог обновиться турбо-фреймом. Редактор в
      // общем VM уже создан, и закрыть его больше будет некому: disconnect
      // прошёл раньше, чем появился send.
      if (!this.element.isConnected) {
        send("close")
        return
      }

      this.send = send
      this.state = state
      this.#busy(false)
      this.render()
    } catch (error) {
      console.error("court diagram", error)
      this.#failed()
    }
  }

  // --- жесты ---------------------------------------------------------------

  selectTool(event) {
    this.#apply("select_tool", { tool: event.currentTarget.dataset.tool })
  }

  start(event) {
    if (this.readonlyValue || !this.send) return
    event.preventDefault()

    const point = this.#point(event)
    this.#apply("pointer_down", { ...point, index: this.#itemIndexAt(event.target) })

    if (this.state.capturing) this.#capture(event)
  }

  move(event) {
    if (!this.state.capturing) return
    event.preventDefault()

    this.#apply("pointer_move", this.#point(event))
  }

  finish(event) {
    if (!this.state.capturing) return

    this.#release(event)
    this.#apply("pointer_up")
  }

  // --- правки --------------------------------------------------------------

  deleteSelected() { this.#apply("delete_selected") }
  clearFrame() { this.#apply("clear_frame") }
  undo() { this.#apply("undo") }
  addFrame() { this.#apply("add_frame") }
  duplicateFrame() { this.#apply("duplicate_frame") }
  deleteFrame() { this.#apply("delete_frame") }

  updateFrameTitle(event) {
    this.#apply("frame_title", { title: event.currentTarget.value })
  }

  selectFrame(event) {
    const index = Number(event.currentTarget.dataset.frameIndex)

    // Кадры листаются и в просмотре, где Ruby не поднимается: показать фазу
    // упражнения — это не правка схемы.
    if (!this.send) {
      this.state = { ...this.state, frame_index: index }
      this.render()
      return
    }

    this.#apply("select_frame", { index })
  }

  #apply(op, args = {}) {
    if (!this.send) return

    this.state = this.send(op, args)
    this.render()
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
    return this.state.frames[this.state.frame_index]
  }

  #renderLayer() {
    const layer = this.layerTarget
    layer.replaceChildren()

    this.frame.arrows.forEach((arrow) => layer.appendChild(this.#arrowNode(arrow)))
    if (this.state.draft) layer.appendChild(this.#arrowNode(this.state.draft, true))
    this.frame.items.forEach((item, index) => layer.appendChild(this.#itemNode(item, index)))
  }

  #renderTabs() {
    if (!this.hasTabsTarget) return

    this.tabsTarget.replaceChildren()
    this.state.frames.forEach((frame, index) => {
      const button = document.createElement("button")
      button.type = "button"
      button.dataset.frameIndex = index
      button.dataset.action = "court-diagram#selectFrame"
      button.textContent = frame.title?.trim() || String(index + 1)
      button.className =
        index === this.state.frame_index
          ? "rounded bg-indigo-600 px-2 py-1 text-xs text-white"
          : "rounded border border-gray-300 px-2 py-1 text-xs text-gray-600 dark:border-white/15 dark:text-slate-300"
      this.tabsTarget.appendChild(button)
    })
  }

  #renderTools() {
    this.toolTargets.forEach((button) => {
      const active = button.dataset.tool === this.state.tool
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
    if (index === this.state.selected) {
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

  // Пока Ruby не поднялся — и всегда в просмотре — рисуем то, что пришло с
  // сервера: там уже нормализованная схема.
  #serverState() {
    const frames = Array.isArray(this.diagramValue?.frames) ? this.diagramValue.frames : []

    return {
      frames: frames.length > 0 ? frames : [ { title: "", items: [], arrows: [] } ],
      frame_index: 0,
      tool: "select",
      selected: null,
      draft: null,
      capturing: false
    }
  }

  // Экран → координаты viewBox. Считаем на каждое событие, а не кэшируем: холст
  // живёт внутри <details> и до раскрытия у него вообще нет размеров.
  // За сетку не обрезаем — это делает Ruby, там же, где обрезает пришедший POST.
  #point(event) {
    const matrix = this.svgTarget.getScreenCTM()
    if (!matrix) return { x: 0, y: 0 }

    const point = new DOMPoint(event.clientX, event.clientY).matrixTransform(matrix.inverse())
    return { x: point.x, y: point.y }
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

  // Кнопки без поднятого Ruby ничего не делают, поэтому на время загрузки они
  // выключены, а не просто молчат в ответ на клик.
  #busy(busy) {
    this.element.querySelectorAll("button[data-action*='court-diagram#']").forEach((button) => {
      button.disabled = busy
    })

    // Поле названия — тоже: набранное до старта редактор не увидит, он соберётся
    // из пришедшего с сервера, и текст останется на экране, но не в схеме.
    if (this.hasFrameTitleTarget) this.frameTitleTarget.disabled = busy

    if (this.hasStatusTarget) this.statusTarget.hidden = !busy
  }

  #failed() {
    if (!this.hasStatusTarget) return

    this.statusTarget.hidden = false
    this.statusTarget.textContent = this.statusTarget.dataset.failedText
  }

  #save() {
    if (this.readonlyValue || !this.hasInputTarget || this.state.value === undefined) return

    this.inputTarget.value = this.state.value
  }
}
