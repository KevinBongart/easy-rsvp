# Identifies a client for abuse limits by a keyed one-way digest of its
# address, never the address itself. IPv6 addresses are reduced to their /64
# prefix, which a single household or host controls.
module ClientDigest
  # Named after its first user, RecentEventCreation; renaming it would change
  # every digest and forget the clients that table currently limits.
  PURPOSE = "recent_event_creations/client_digest"

  def self.for(remote_ip)
    OpenSSL::HMAC.hexdigest("SHA256", key, client_key(remote_ip))
  end

  def self.client_key(remote_ip)
    address = IPAddr.new(remote_ip.to_s)
    address = address.mask(64) if address.ipv6? && !address.ipv4_mapped?
    address.to_s
  rescue IPAddr::InvalidAddressError
    remote_ip.to_s
  end
  private_class_method :client_key

  def self.key
    Rails.application.key_generator.generate_key(PURPOSE, 32)
  end
  private_class_method :key
end
