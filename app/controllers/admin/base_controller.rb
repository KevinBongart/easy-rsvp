module Admin
  class BaseController < ApplicationController
    before_action :set_event

    private

    def set_event
      hashid = hashid_from_param(params[:event_id])
      id = Event.decode_id(hashid)

      @event = Event.find_by!(id: id, admin_token: params[:admin_admin_token])
    end

    def hashid_from_param(parameterized_id)
      parameterized_id.to_s.split('-').first
    end
  end
end
