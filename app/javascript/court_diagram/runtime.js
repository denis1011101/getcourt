// Мост между Stimulus и редактором схемы, который живёт в Ruby.
//
// Один VM на страницу: в библиотеке блоков редакторов столько же, сколько
// блоков, а рантайм ruby.wasm — это два десятка мегабайт и секунды на старт.
// Поэтому VM общий, а редакторы в нём нумерованные.

// Версия рантайма прибита гвоздями: обёртка и .wasm обязаны быть из одной сборки.
const WASM_VERSION = "2.7.2"
const WASM_URL = `https://cdn.jsdelivr.net/npm/@ruby/3.4-wasm-wasi@${WASM_VERSION}/dist/ruby+stdlib.wasm`

// Аргументы жеста ходят через глобалку, а не подставляются в vm.eval: подпись
// фигуры и название кадра — это пользовательский текст, а внутри двойных
// кавычек Ruby #{...} исполняется. Через глобалку интерполировать нечего.
const MAILBOX = "__courtDiagram"

// Единственный кусок Ruby, которого нет на сервере: там неоткуда взяться JS.
const BRIDGE = String.raw`
  require "js"
  require "json"

  module CourtDiagramBridge
    EDITORS = {}

    def self.call(id)
      request = JSON.parse(JS.global[:${MAILBOX}].to_s)

      op = request["op"]

      # Редактор пережил свой блок: страница свернула схему или её заменил Turbo.
      if op == "close"
        EDITORS.delete(id)
        return JSON.generate({})
      end

      # "open" — это просто первое обращение: apply такой операции не знает.
      editor = EDITORS[id] ||= TrainingBlock::Diagram::Editor.new(request.dig("args", "diagram"))
      editor.apply(op, request["args"])

      JSON.generate(editor.state)
    end
  end
`

let vmPromise = null
let lastId = 0

function bootVm(sourceUrl) {
  // Грузим по требованию: страница без редактора не должна платить даже за
  // обёртку, а лениво загружаемый Stimulus-контроллер приходит уже по делу.
  vmPromise ||= (async () => {
    const [ { DefaultRubyVM }, wasm, source ] = await Promise.all([
      import("@ruby/wasm-wasi"),
      WebAssembly.compileStreaming(fetch(WASM_URL)),
      fetch(sourceUrl).then((response) => {
        if (!response.ok) throw new Error(`court diagram source: ${response.status}`)
        return response.text()
      })
    ])

    const { vm } = await DefaultRubyVM(wasm)
    vm.eval(source)
    vm.eval(BRIDGE)
    return vm
  })()

  // Уроненный VM не должен отравить страницу навсегда: следующий редактор
  // (или следующая попытка) начнёт загрузку заново.
  vmPromise.catch(() => { vmPromise = null })

  return vmPromise
}

// Возвращает функцию «отправить жест — получить снимок состояния».
export async function openEditor(sourceUrl, diagram) {
  const vm = await bootVm(sourceUrl)
  const id = ++lastId

  const send = (op, args = {}) => {
    window[MAILBOX] = JSON.stringify({ op, args })
    return JSON.parse(vm.eval(`CourtDiagramBridge.call(${id})`).toString())
  }

  return { send, state: send("open", { diagram }) }
}
