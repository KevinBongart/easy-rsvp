class OrganizerController < ApplicationController
  before_action :set_event

  private

  def set_event
    link_id = event_link_id_from_param(params[:event_id])
    @event = Event.where(admin_token: params[:admin_admin_token]).find_by_link_id!(link_id)
    render_removed_event if @event.spam_locked?
  end
end
