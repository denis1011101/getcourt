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
