# Lets the site administrator view pages guests can no longer see (spam and
# unpublished events, and organizer pages locked by an operator spam mark),
# and mark events as spam from them.
#
# Loading the Basic-Auth-protected dashboard opens an admin session: an
# expiring flag in the Rails session cookie, which is encrypted and signed, so
# it cannot be forged and never appears in URLs or logs.
module AdminPreview
  SESSION_KEY = :admin_preview_until
  EXPIRES_IN = 1.day

  def self.start(session)
    session[SESSION_KEY] = EXPIRES_IN.from_now.to_i
  end

  def self.active?(session)
    session[SESSION_KEY].to_i > Time.current.to_i
  end

  def self.stop(session)
    session.delete(SESSION_KEY)
  end
end
