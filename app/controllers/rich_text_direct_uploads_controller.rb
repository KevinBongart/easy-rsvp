class RichTextDirectUploadsController < ActiveStorage::DirectUploadsController
  CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  MAXIMUM_SIZE = 10.megabytes

  def create
    if acceptable_upload?
      super
    else
      render json: { error: "Upload must be a PNG, JPEG, GIF, or WebP image between 1 byte and 10 MB." },
        status: :unprocessable_content
    end
  end

  private

  def acceptable_upload?
    attributes = blob_args
    byte_size = Integer(attributes[:byte_size], exception: false)

    CONTENT_TYPES.include?(attributes[:content_type]) && byte_size&.between?(1, MAXIMUM_SIZE)
  end
end
