namespace :spam do
  desc "Delete images embedded in events marked as spam by an operator more than 30 days ago"
  task purge_images: :environment do
    # One line on stdout, where Dokku collects cron output: counts and bytes only.
    puts Event::SpamImages.purge_expired
  end
end
