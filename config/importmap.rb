# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# config/importmap.rb
pin "chart.js", to: "https://ga.jspm.io/npm:chart.js@4.5.1/dist/chart.js"
pin "@kurkle/color", to: "https://ga.jspm.io/npm:@kurkle/color@0.3.4/dist/color.esm.js"
pin "@js-from-routes/client", to: "@js-from-routes--client.js" # @1.0.4
pin "@js-from-routes/core", to: "@js-from-routes--core.js" # @1.0.3
pin "gridjs" # @6.2.0

pin_all_from "app/javascript/api", under: "api"
