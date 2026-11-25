# The events this browser created or opened with a valid organizer link, so
# their creator can see confidently flagged spam as if it were live (see
# Event#confidently_spam?). Lives in the encrypted Rails session cookie, like
# AdminPreview.
module ManagedEvents
  # The underscore keeps OwnedRsvps from taking it for an old per-event key.
  SESSION_KEY = "managed_event_hashids".freeze
  LIMIT = 20

  # Keeps the most recently managed hashids, oldest first, without duplicates.
  def self.remember(session, event)
    hashids = Array(session[SESSION_KEY]) - [ event.hashid ]
    session[SESSION_KEY] = (hashids << event.hashid).last(LIMIT)
  end

  def self.include?(session, event)
    Array(session[SESSION_KEY]).include?(event.hashid)
  end
end
