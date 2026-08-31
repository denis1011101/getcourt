# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@rails/ujs", to: "@rails--ujs.js" # @7.1.3
# ahoy: the ahoy_matey gem only wires its ahoy.js for Sprockets, so under
# Propshaft we vendor the gem's ahoy.js into vendor/javascript and pin it here.
pin "ahoy", to: "ahoy.js" # ahoy.js 0.4.5, copied from the ahoy_matey gem

# ruby.wasm для редактора схемы корта: в браузере крутится тот же
# TrainingBlock::Diagram, что и на сервере (app/javascript/court_diagram).
# preload: false — рантайм нужен на одной странице и весит два десятка мегабайт,
# так что и обёртку тянем только по требованию.
pin "@ruby/wasm-wasi", to: "https://cdn.jsdelivr.net/npm/@ruby/wasm-wasi@2.7.2/dist/browser/+esm", preload: false
pin_all_from "app/javascript/court_diagram", under: "court_diagram", preload: false
