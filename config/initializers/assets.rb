# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add Subresource Integrity hashes to asset tags.
Rails.application.config.assets.integrity_hash_algorithm = "sha256"

# Dart Sass consumes these source files; Propshaft should publish only the
# compiled bundle under app/assets/builds.
Rails.application.config.assets.excluded_paths << Rails.root.join("app/assets/stylesheets")
