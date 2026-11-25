# The RSVPs this browser sent, so their guest can delete them. Lives in the
# encrypted Rails session cookie next to ManagedEvents, so the list is capped:
# browsers reject cookies over 4 KB and Rails raises CookieOverflow first.
module OwnedRsvps
  SESSION_KEY = "owned_rsvp_hashids".freeze
  # With 100 hashids plus ManagedEvents' 20, the session id, the CSRF token and
  # a flash message, the worst case measures about 2.75 KB with today's
  # 7-character production hashids and 3 KB with 8-character ones (ids around
  # 10 million; see spec/requests/rsvp_session_size_spec.rb).
  LIMIT = 100

  # Keeps the most recent hashids, oldest first. Older RSVPs stay on their
  # events; this browser just can no longer delete them.
  def self.remember(session, rsvp)
    session[SESSION_KEY] = (hashids(session) << rsvp.hashid).last(LIMIT)
  end

  def self.forget(session, rsvp)
    session[SESSION_KEY] = hashids(session) - [ rsvp.hashid ]
  end

  def self.include?(session, rsvp)
    hashids(session).include?(rsvp.hashid)
  end

  # Sessions used to hold one top-level key per event (its hashid) listing that
  # event's RSVP hashids, and overflowed after about 100 events. Those keys are
  # folded into the capped list the first time it is read, so returning guests
  # keep their delete links.
  def self.hashids(session)
    legacy_keys = session.keys.select { |key| session[key].is_a?(Array) && Event.decode_id(key) }
    return Array(session[SESSION_KEY]) if legacy_keys.empty?

    legacy_hashids = legacy_keys.flat_map { |key| session.delete(key) }
    session[SESSION_KEY] = (legacy_hashids + Array(session[SESSION_KEY])).last(LIMIT)
  end
end
