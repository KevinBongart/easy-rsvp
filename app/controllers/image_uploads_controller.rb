class ImageUploadsController < ApplicationController
  rate_limit to: 20, within: 1.minute, only: :create, with: :upload_rate_limited

  def direct_upload_disabled
    head :not_found
  end

  def create
    attributes = image_upload_params
    upload_token = submitted_upload_token
    unless registered_image_upload_token?(upload_token)
      render json: { image: ["upload session is invalid or expired"] }, status: :forbidden
      return
    end

    file = attributes[:image]
    if file.present? && !file.is_a?(ActionDispatch::Http::UploadedFile)
      render json: { image: ["must be an uploaded image file"] }, status: :unprocessable_entity
      return
    end

    @image_upload = ImageUpload.new(
      attributes.merge(upload_session_digest: ImageUpload.digest_token(upload_token))
    )
    if file.present?
      # Do not trust a client-supplied MIME type or filename extension.
      @image_upload.image.blob.content_type = Marcel::MimeType.for(file.tempfile)
    end

    respond_to do |format|
      if @image_upload.save
        format.json { render json: { url: url_for(@image_upload.image) }, status: :ok }
      else
        format.json { render json: @image_upload.errors, status: :unprocessable_entity }
      end
    end
  end

  private

  def upload_rate_limited
    render json: { image: ["too many uploads; please wait and try again"] }, status: :too_many_requests
  end

  def image_upload_params
    params.require(:image_upload).permit(:image)
  end

  def submitted_upload_token
    upload_params = params[:image_upload]
    upload_params[:token] if upload_params.is_a?(ActionController::Parameters)
  end
end
