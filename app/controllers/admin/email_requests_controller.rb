module Admin
  class EmailRequestsController < BaseController
    def create
      email_address = email_address_param

      if email_address_param.blank?
        redirect_to event_admin_path(@event, @event.admin_token), alert: "Please enter your email address"
      else
        UserMailer.admin_url_request_email(email_address, @event).deliver_now
        redirect_to event_admin_path(@event, @event.admin_token), notice: "The admin link has been sent to #{email_address_param}"
      end
    end

    private

    def email_address_param
      params[:email]
    end
  end
end
