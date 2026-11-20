namespace :images do
  desc "Delete images of expired spam and images no event uses (DRY_RUN=1 lists them without deleting)"
  task purge: :environment do
    # Dokku collects cron output from stdout: one line per deleted blob (id,
    # key, bytes, reason) and a summary, never event content.
    logger = ActiveSupport::Logger.new($stdout)
    result = ImageCleanup.run(dry_run: ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"]) || false, logger:)
    puts result
    # A non-zero exit makes failed storage deletes visible in Dokku's cron logs.
    exit 1 unless result.success?
  end
end
