class ImageUploadsController < ApplicationController
  def create
    @image_upload = ImageUpload.new(image_upload_params)

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
