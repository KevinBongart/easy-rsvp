class AddOwnershipToImageUploads < ActiveRecord::Migration[8.1]
  def change
    add_reference :image_uploads, :event, foreign_key: true
    add_column :image_uploads, :upload_session_digest, :string
    add_index :image_uploads, :upload_session_digest
  end
end
