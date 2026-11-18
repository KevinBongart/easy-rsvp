# Lets the site administrator view pages guests can no longer see (spam and
# unpublished events, and organizer pages locked by an operator spam mark).
#
# Tokens are signed with the app's secret key, bound to one event, and expire,
# so nothing is stored and a leaked link stops working. The parameter name
# contains "token", so Rails filters it from request logs.
module AdminPreview
  PARAM = :preview_token
  EXPIRES_IN = 1.day

  def self.token_for(event)
    verifier.generate(event.id, purpose: :admin_event_preview, expires_in: EXPIRES_IN)
  end

  def self.valid?(event, token)
    token.is_a?(String) && verifier.verified(token, purpose: :admin_event_preview) == event.id
  end

  def self.verifier
    Rails.application.message_verifier("admin_event_preview")
  end
  private_class_method :verifier
end
