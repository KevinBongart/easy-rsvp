enable_integrity!

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers", preload: true
pin "trix", preload: true
pin "@rails/actiontext", to: "actiontext.esm.js", preload: true

# Bootstrap 4 stays in place during the asset-pipeline migration. These ESM
# downloads are managed by bin/importmap and avoid the old Sprockets wrappers.
pin "bootstrap", preload: true # @4.6.2
pin "jquery", preload: true # @3.7.1
pin "popper.js", preload: true # @1.16.1
