class ImageUpload < ApplicationRecord
  CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  MAXIMUM_SIZE = 10.megabytes

  has_one_attached :image

  validate :acceptable_image

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
