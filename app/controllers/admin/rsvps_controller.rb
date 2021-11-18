module Admin
  class RsvpsController < BaseController
    before_action :set_rsvp

    def update
      if @rsvp.update(rsvp_params)
        redirect_to event_admin_path(@event, @event.admin_token), notice: 'The RSVP was updated.'
      else
        redirect_to event_admin_path(@event, @event.admin_token), alert: "The RSVP could not be updated: #{@rsvp.errors.full_messages.join(', ')}"
      end
    end

    def destroy
      @rsvp.destroy

      redirect_to event_admin_path(@event, @event.admin_token), notice: 'The RSVP was deleted.'
    end

    private

    def set_rsvp
      @rsvp = @event.rsvps.find(params[:id])
    end

    def rsvp_params
      params.require(:rsvp).permit(:name, :response)
    end
  end
end
