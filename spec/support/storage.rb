require 'tmpdir'

storage_root = nil

RSpec.configure do |config|
  config.before(:suite) do
    # DiskService writes survive database rollbacks; use a dedicated process directory.
    storage_root = Dir.mktmpdir('easy-rsvp-spec-storage-')
    ActiveStorage::Blob.services.fetch(:test).root = storage_root
  end
  config.after(:suite) do
    FileUtils.remove_entry(storage_root) if storage_root && File.exist?(storage_root)
  end
end
