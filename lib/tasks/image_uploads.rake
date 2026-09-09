namespace :image_uploads do
  desc "Purge managed editor uploads that have been abandoned for at least 24 hours"
  task purge_abandoned: :environment do
    unless Rails.env.production? || Rails.env.test?
      abort "Refusing to purge outside production; an imported development database may still reference production storage."
    end

    count = ImageUpload.purge_abandoned!
    puts "Purged #{count} abandoned image upload#{'s' unless count == 1}."
  end
end
