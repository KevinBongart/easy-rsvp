module ImageUploadSessions
  extend ActiveSupport::Concern

  MAXIMUM_OPEN_SESSIONS = 8
  SESSION_KEY = :image_upload_session_digests

  private

  def prepare_image_upload_token
    candidate = params[:image_upload_token]
    @image_upload_token = if registered_image_upload_token?(candidate)
      candidate
    else
      register_image_upload_token
    end
  end

  def registered_image_upload_token?(candidate)
    return false unless candidate.is_a?(String) && candidate.present?

    digest = ImageUpload.digest_token(candidate)
    Array(session[SESSION_KEY]).any? do |registered_digest|
      registered_digest.bytesize == digest.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(registered_digest, digest)
    end
  end

  def register_image_upload_token
    token = SecureRandom.urlsafe_base64(32)
    digests = Array(session[SESSION_KEY]).last(MAXIMUM_OPEN_SESSIONS - 1)
    session[SESSION_KEY] = digests << ImageUpload.digest_token(token)
    token
  end

  def claim_image_uploads(event)
    event.claim_image_uploads!(@image_upload_token)
    retire_image_upload_token(@image_upload_token)
  end

  def retire_image_upload_token(token)
    digest = ImageUpload.digest_token(token)
    remaining = Array(session[SESSION_KEY]).reject do |registered_digest|
      registered_digest.bytesize == digest.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(registered_digest, digest)
    end
    remaining.empty? ? session.delete(SESSION_KEY) : session[SESSION_KEY] = remaining
  end
end
