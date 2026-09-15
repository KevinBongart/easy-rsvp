class EventsAdminController < ApplicationController
  before_action :set_event

  def show
    @rsvps = @event.rsvps.persisted.order(created_at: :asc)
  end

  def edit
  end

  def update
    if @event.update(event_params)
      redirect_to event_admin_path(@event, @event.admin_token), notice: 'Your event was updated.'
    else
      render :edit
    end
  end

  def destroy
    @event.destroy
    redirect_to root_path, notice: 'Event was successfully destroyed.'
  end

  def toggle_publish
    @event.toggle!(:published)
    redirect_to event_admin_path(@event, @event.admin_token), notice: "Your event is now #{@event.published? ? 'live' : 'unpublished'}."
  end

  private

  def set_event
    hashid = hashid_from_param(params[:event_id])
    id = Event.decode_id(hashid)

    @event = Event.find_by!(id: id, admin_token: params[:admin_token])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def event_params
    params.require(:event).permit(:title, :date, :body, :show_rsvp_names)
  end

  def hashid_from_param(parameterized_id)
    parameterized_id.to_s.split('-').first
  end
end
