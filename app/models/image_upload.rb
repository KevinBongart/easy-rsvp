class ImageUpload < ApplicationRecord
  CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  MAXIMUM_SIZE = 10.megabytes
  ABANDONED_AFTER = 24.hours

  belongs_to :event, optional: true
  has_one_attached :image

  validate :acceptable_image

  scope :claimable_by, ->(token, at: Time.current) {
    where(event_id: nil, upload_session_digest: digest_token(token))
      .where(created_at: (at - ABANDONED_AFTER)..)
  }
  scope :abandoned, ->(at: Time.current) {
    where(event_id: nil)
      .where.not(upload_session_digest: nil)
      .where(created_at: ...(at - ABANDONED_AFTER))
  }

  def self.digest_token(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.purge_abandoned!(at: Time.current)
    count = 0
    abandoned(at: at).find_each do |upload|
      upload.image.purge
      upload.destroy!
      count += 1
    end
    count
  end

  private

  def acceptable_image
    unless image.attached?
      errors.add(:image, "must be attached")
      return
    end

    unless CONTENT_TYPES.include?(image.blob.content_type)
      errors.add(:image, "must be a PNG, JPEG, GIF, or WebP image")
    end
    errors.add(:image, "must be 10 MB or smaller") if image.blob.byte_size > MAXIMUM_SIZE
  end
end
