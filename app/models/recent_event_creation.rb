# Limits how many events one client can create in a short window, and refuses
# clients whose recent event is currently spam.
#
# Clients are identified by a keyed one-way digest of their address, never the
# address itself, and the digest is never stored on the event. IPv6 addresses
# are reduced to their /64 prefix, which a single household or host controls.
# Each row links to the event it created; the link lives only in this table
# and is deleted with the row once older than FLAGGED_BLOCK.
class RecentEventCreation < ApplicationRecord
  LIMIT = 5
  WINDOW = 30.minutes
  # A client is refused while any event it created this recently is spam. The
  # event's current state counts, so a flag set seconds later by the
  # background review blocks the next attempt, and an organizer who edits a
  # wrongly flagged event until the flag clears is unblocked at once.
  # Rows are kept this long, which also covers WINDOW.
  FLAGGED_BLOCK = 2.hours
  DIGEST_PURPOSE = "recent_event_creations/client_digest"

  belongs_to :event, optional: true

  # Yields when the client may create an event; the block returns the saved
  # event, or false when it was not saved. Records a creation linked to that
  # event and returns the block's result, or :limited without yielding.
  # Concurrent requests from the same client are serialized so parallel bursts
  # cannot exceed the limit.
  def self.limit(remote_ip)
    digest = digest_for(remote_ip)

    # Clean up outside the locked transaction so its row locks never make one
    # client's creation wait for another client's.
    where(created_at: ...FLAGGED_BLOCK.ago).delete_all

    transaction do
      lock_client(digest)

      if limited?(digest)
        :limited
      else
        created = yield
        create!(client_digest: digest, event: created) if created
        created
      end
    end
  end

  def self.digest_for(remote_ip)
    OpenSSL::HMAC.hexdigest("SHA256", digest_key, client_key(remote_ip))
  end

  # One query on the (client_digest, created_at) index over the client's rows
  # from the last FLAGGED_BLOCK: how many fall in the rate window, and whether
  # any of their events is currently spam.
  def self.limited?(digest)
    now = Time.current
    recent, flagged = left_joins(:event)
      .where(client_digest: digest, created_at: (now - FLAGGED_BLOCK)..)
      .pick(
        Arel.sql(sanitize_sql([ "COUNT(*) FILTER (WHERE recent_event_creations.created_at >= ?)", now - WINDOW ])),
        Arel.sql("COALESCE(BOOL_OR(events.spam_at IS NOT NULL), FALSE)")
      )

    recent >= LIMIT || flagged
  end
  private_class_method :limited?

  def self.client_key(remote_ip)
    address = IPAddr.new(remote_ip.to_s)
    address = address.mask(64) if address.ipv6? && !address.ipv4_mapped?
    address.to_s
  rescue IPAddr::InvalidAddressError
    remote_ip.to_s
  end
  private_class_method :client_key

  def self.digest_key
    Rails.application.key_generator.generate_key(DIGEST_PURPOSE, 32)
  end
  private_class_method :digest_key

  def self.lock_client(digest)
    connection.execute(
      sanitize_sql([ "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))", digest ])
    )
  end
  private_class_method :lock_client
end
