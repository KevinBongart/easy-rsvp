class AdminEmailRequestsController < ApplicationController
  before_action :set_event

  def create
    email_address = email_address_param
    if email_address_param.blank?
      redirect_to event_admin_path(@event, @event.admin_token), alert: "Please enter your email address"
    else
      # TODO: email!
      redirect_to event_admin_path(@event, @event.admin_token), notice: "The admin link has been sent to #{email_address_param}"
    end
  end

  private

  def set_event
    hashid = hashid_from_param(params[:event_id])
    id = Event.decode_id(hashid)

    @event = Event.find_by!(id: id, admin_token: params[:admin_admin_token])
  end

  def hashid_from_param(parameterized_id)
    parameterized_id.to_s.split('-').first
  end

  def email_address_param
    params[:email]
  end
end
