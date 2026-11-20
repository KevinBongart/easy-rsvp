# The Rails default the original Active Storage migration here lacked. Besides
# keeping attachments consistent, it makes ImageCleanup safe against an event
# save that attaches a blob while the cleanup deletes it: the insert locks the
# blob row, so one of the two waits and then fails instead of leaving an
# attachment to a deleted file.
#
# The 2026-11-20 production copy had 16 legacy ImageUpload attachments whose
# blob was already gone; they and their ImageUpload rows go first.
class AddBlobForeignKeyToActiveStorageAttachments < ActiveRecord::Migration[8.1]
  class Attachment < ActiveRecord::Base
    self.table_name = "active_storage_attachments"
  end

  class Blob < ActiveRecord::Base
    self.table_name = "active_storage_blobs"
  end

  class ImageUpload < ActiveRecord::Base
    self.table_name = "image_uploads"
  end

  def up
    dangling = Attachment.where.not(blob_id: Blob.select(:id))
    ImageUpload.where(id: dangling.where(record_type: "ImageUpload").select(:record_id)).delete_all
    dangling.delete_all

    add_foreign_key :active_storage_attachments, :active_storage_blobs, column: :blob_id
  end

  def down
    remove_foreign_key :active_storage_attachments, column: :blob_id
  end
end
