class EventsAdminController < ApplicationController
  before_action :set_event

  def show
  end

  def edit
  end

  def update
    respond_to do |format|
      if @event.update(event_params)
        format.html { redirect_to @event, notice: 'Event was successfully updated.' }
        format.json { render :show, status: :ok, location: @event }
      else
        format.html { render :edit }
        format.json { render json: @event.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @event.destroy
    respond_to do |format|
      format.html { redirect_to events_url, notice: 'Event was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private

  def set_event
    hashid = hashid_from_param(params[:event_id])
    id = Event.decode_id(hashid)

    @event = Event.find_by!(id: id, admin_token: params[:admin_token])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def event_params
    params.require(:event).permit(:title, :date, :body, :admin_token)
  end

  def hashid_from_param(parameterized_id)
    parameterized_id.to_s.split('-').first
  end
end
