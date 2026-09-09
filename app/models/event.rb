class Event < ApplicationRecord
  include Hashid::Rails

  has_many :rsvps, dependent: :destroy
  has_many :image_uploads, dependent: :destroy

  before_create :set_admin_token

  validates :title, presence: true
  validates :date, presence: true

  def to_param
    "#{hashid}-#{title.parameterize}"
  end

  def claim_image_uploads!(upload_token)
    referenced_ids = ImageUpload.claimable_by(upload_token)
      .includes(image_attachment: :blob)
      .filter_map do |upload|
        upload.id if body.to_s.include?(upload.image.blob.signed_id)
      end

    return 0 if referenced_ids.empty?

    ImageUpload.where(id: referenced_ids, event_id: nil).update_all(
      event_id: id,
      upload_session_digest: nil,
      updated_at: Time.current
    )
  end

  private

  def set_admin_token
    self.admin_token = SecureRandom.uuid
  end
end
