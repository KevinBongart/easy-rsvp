class RichTextDirectUploadsController < ActiveStorage::DirectUploadsController
  CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  MAXIMUM_SIZE = 5.megabytes
  LIMITED_MESSAGE = "To prevent abuse on Easy RSVP, we're limiting how many images you can upload in a short window. Please try again later.".freeze
  # Uploads per client, counted whether or not they are accepted. On the
  # 2026-11-20 production copy no legitimate event embedded more than 2
  # images (spam: 3), and the busiest 10 minutes of the last 120 days saw 18
  # uploads site-wide. The daily cap bounds what one address can store
  # (60 × 5 MB) without ever creating an event.
  BURST_LIMIT = 20
  BURST_WINDOW = 10.minutes
  DAILY_LIMIT = 60
  DAILY_WINDOW = 1.day

  include RateLimitedPerClient

  rate_limit_per_client to: BURST_LIMIT, within: BURST_WINDOW, message: LIMITED_MESSAGE, name: "burst", only: :create
  rate_limit_per_client to: DAILY_LIMIT, within: DAILY_WINDOW, message: LIMITED_MESSAGE, name: "daily", only: :create

  def create
    if acceptable_upload?
      super
    else
      render json: { error: "Upload must be a PNG, JPEG, GIF, or WebP image between 1 byte and 5 MB." },
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
