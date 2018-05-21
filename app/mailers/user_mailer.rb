class UserMailer < ApplicationMailer
  def admin_url_request_email(email_address, event)
    @event = event
    mail(to: email_address, subject: "Easy RSVP: #{event.title}")
  end
end
