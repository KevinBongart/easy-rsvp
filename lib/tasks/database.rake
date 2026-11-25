require Rails.root.join("lib/production_database_pull")

namespace :db do
  desc "Create, encrypt, and download a timestamped production database backup"
  task backup_production: :environment do
    ProductionDatabasePull.new(
      database_config: ActiveRecord::Base.connection_db_config,
      rails_environment: Rails.env,
      rails_command: Rails.root.join("bin/rails"),
      backup_dir: Rails.root.join("db/backups"),
      disconnect: -> { ActiveRecord::Base.connection_pool.disconnect! }
    ).backup
  rescue ProductionDatabasePull::Error => error
    abort error.message
  end

  desc "Copy the Dokku production database into the local development database"
  task pull_production: :environment do
    ProductionDatabasePull.new(
      database_config: ActiveRecord::Base.connection_db_config,
      rails_environment: Rails.env,
      rails_command: Rails.root.join("bin/rails"),
      backup_dir: Rails.root.join("tmp/database_backups"),
      disconnect: -> { ActiveRecord::Base.connection_pool.disconnect! }
    ).call
  rescue ProductionDatabasePull::Error => error
    abort error.message
  end

  desc "Decrypt a production backup (BACKUP=path, default newest) into the local development database"
  task restore_production_backup: :environment do
    backup = ENV["BACKUP"].presence || Dir[Rails.root.join("db/backups/easy-rsvp-production-*.pgdump.gpg")].max
    abort "No encrypted production backup found. Run db:backup_production or set BACKUP." unless backup

    ProductionDatabasePull.new(
      database_config: ActiveRecord::Base.connection_db_config,
      rails_environment: Rails.env,
      rails_command: Rails.root.join("bin/rails"),
      backup_dir: Rails.root.join("tmp/database_backups"),
      disconnect: -> { ActiveRecord::Base.connection_pool.disconnect! }
    ).restore_backup(backup)
  rescue ProductionDatabasePull::Error => error
    abort error.message
  end
end
