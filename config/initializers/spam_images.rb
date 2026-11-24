# Every route that serves a blob or a representation by signed id goes through
# one of these controllers (ActiveStorage::SetBlob#set_blob calls blob_scope).
# Production stores files on S3, so the disk controller is not involved there.
Rails.application.config.to_prepare do
  [
    ActiveStorage::Blobs::RedirectController,
    ActiveStorage::Blobs::ProxyController,
    ActiveStorage::Representations::RedirectController,
    ActiveStorage::Representations::ProxyController
  ].each { |controller| controller.prepend(HidesOperatorSpamImages) }
end
