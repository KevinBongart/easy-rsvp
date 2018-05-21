class ImagesController < ApplicationController
  def create
    @image = Image.new(image_params)

    respond_to do |format|
      if @image.save
        format.json { render json: { url: url_for(@image.image) }, status: :ok }
      else
        format.json { render json: @image.errors, status: :unprocessable_entity }
      end
    end
  end

  private

  def image_params
    params.require(:image).permit(:image)
  end
end
