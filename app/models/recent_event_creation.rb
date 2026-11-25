# Limits how many events one client can create in a short window, and refuses
# clients who recently created spam.
#
# Clients are identified by a keyed one-way digest of their address, never the
# address itself, and the digest is never stored on the event. IPv6 addresses
# are reduced to their /64 prefix, which a single household or host controls.
# Each row links to the event it created; the link lives only in this table
# and the row is deleted on the first creation attempt after it is older than
# SPAM_BLOCK.
class RecentEventCreation < ApplicationRecord
  LIMIT = 5
  WINDOW = 30.minutes
  # A client is refused while any event it created this recently became spam,
  # whatever decided it: the Ruby rules, the background review, or an
  # operator. The row records it (spam_at) and keeps it: deleting the event or
  # editing the spam away does not lift the block, since the code is public
  # and either would otherwise cost a spammer one request. Only an operator's
  # "Not spam" or this expiry lifts it. Rows are kept this long, which also
  # covers WINDOW.
  SPAM_BLOCK = 2.hours
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
    where(created_at: ...SPAM_BLOCK.ago).delete_all

    transaction do
      lock_client(digest)

      if limited?(digest)
        :limited
      else
        created = yield
        create!(client_digest: digest, event: created, spam_at: created.spam_at) if created
        created
      end
    end
  end

  # Called wherever an event becomes spam: Event's after_save callback, and
  # Event#flag_as_spam! and #mark_as_spam!, which skip callbacks.
  def self.record_spam!(event)
    where(event_id: event.id, spam_at: nil).update_all(spam_at: Time.current)
  end

  # An operator decided the event is not spam (Event#mark_as_not_spam!).
  def self.clear_spam!(event)
    where(event_id: event.id).update_all(spam_at: nil)
  end

  def self.digest_for(remote_ip)
    OpenSSL::HMAC.hexdigest("SHA256", digest_key, client_key(remote_ip))
  end

  # One query on the (client_digest, created_at) index. A client has at most
  # LIMIT rows per WINDOW, so the rows from the last SPAM_BLOCK are few.
  def self.limited?(digest)
    rows = where(client_digest: digest, created_at: SPAM_BLOCK.ago..).pluck(:created_at, :spam_at)
    window_start = WINDOW.ago

    rows.any? { |_, spam_at| spam_at } || rows.count { |created_at, _| created_at >= window_start } >= LIMIT
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
