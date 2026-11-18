# Limits how many events one client can create in a short window.
#
# Clients are identified by a keyed one-way digest of their address, never the
# address itself, and the digest is never stored on the event. IPv6 addresses
# are reduced to their /64 prefix, which a single household or host controls.
# Rows expire with the window and are deleted as new events are created.
class RecentEventCreation < ApplicationRecord
  LIMIT = 5
  WINDOW = 30.minutes
  DIGEST_PURPOSE = "recent_event_creations/client_digest"

  # Yields when the client is below the limit and records a creation when the
  # block returns true. Returns :limited without yielding otherwise.
  # Concurrent requests from the same client are serialized so parallel bursts
  # cannot exceed the limit.
  def self.limit(remote_ip)
    digest = digest_for(remote_ip)

    # Clean up outside the locked transaction so its row locks never make one
    # client's creation wait for another client's.
    where(created_at: ...WINDOW.ago).delete_all

    transaction do
      lock_client(digest)

      if where(client_digest: digest, created_at: WINDOW.ago..).count >= LIMIT
        :limited
      else
        created = yield
        create!(client_digest: digest) if created
        created
      end
    end
  end

  def self.digest_for(remote_ip)
    OpenSSL::HMAC.hexdigest("SHA256", digest_key, client_key(remote_ip))
  end

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
