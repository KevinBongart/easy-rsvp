class ImageUploadsController < ApplicationController
  def create
    attributes = image_upload_params
    file = attributes[:image]
    if file.present? && !file.is_a?(ActionDispatch::Http::UploadedFile)
      render json: { image: ["must be an uploaded image file"] }, status: :unprocessable_entity
      return
    end

    @image_upload = ImageUpload.new(attributes)
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

  def image_upload_params
    params.require(:image_upload).permit(:image)
  end
end
