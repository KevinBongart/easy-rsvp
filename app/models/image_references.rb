# The stored images that event descriptions point at, read from the HTML
# itself rather than from attachment rows. The former Trix uploader
# (ImageUpload, until September 2026) put only an Active Storage URL in the
# description, so its images have no row tying them to an event, and pasted
# HTML can point at any image the same way. Three forms count:
#
# - Active Storage URLs (blobs and representations, redirect or proxy, any
#   host), whose path carries the blob's signed id, possibly URL-escaped;
# - Action Text `sgid` attributes, which normally also have an attachment row;
# - blob keys, as they appear in direct storage URLs.
#
# Signed ids are decoded without checking their signature. A reference only
# ever keeps an image, and a forged one cannot serve it, so trusting it costs
# storage at most; checking it would delete real images if the secret changed.
class ImageReferences
  ACTIVE_STORAGE_URL = %r{/rails/active_storage/(?:blobs|representations)/(?:redirect/|proxy/)?([^/?#"'\s<>&]+)}
  SIGNED_GLOBAL_ID = /sgid=["']([^"']+)/
  # Keys are SecureRandom.base36(28).
  BLOB_KEY = /(?<![a-z0-9])[a-z0-9]{28}(?![a-z0-9])/
  BLOB_GLOBAL_ID = %r{ActiveStorage::Blob/(\d+)}n
  MARSHAL_INTEGER = "\x04\bi".b

  # Scans the descriptions of `events` in batches; about 85 MB of HTML on the
  # 2026-11 production copy.
  def self.in_descriptions_of(events, batch_size: 1_000)
    new.tap do |references|
      # The stored HTML as is: parsing it into ActionText::Content would cost
      # minutes and could normalize away what we are looking for.
      ActionText::RichText.where(record_type: "Event", name: "body", record_id: events.select(:id))
        .select(:id, :body).find_each(batch_size:) { references.add(it.body_before_type_cast) }
    end
  end

  # The same, one set per event, keyed by event id.
  def self.by_event(events, batch_size: 1_000)
    ActionText::RichText.where(record_type: "Event", name: "body", record_id: events.select(:id))
      .select(:id, :record_id, :body).find_each(batch_size:)
      .to_h { |text| [ text.record_id, new.tap { it.add(text.body_before_type_cast) } ] }
  end

  def initialize
    @blob_ids = Set.new
    @keys = Set.new
  end

  def add(html)
    return if html.blank?

    # JSON inside data-trix-attachment attributes may escape its slashes.
    html = html.gsub("\\/", "/")
    html.scan(ACTIVE_STORAGE_URL) { |(segment)| unescapings(segment).each { @blob_ids.merge(signed_blob_ids(it)) } }
    html.scan(SIGNED_GLOBAL_ID) { |(sgid)| @blob_ids.merge(signed_blob_ids(sgid)) }
    @keys.merge(html.scan(BLOB_KEY))
  end

  def include?(blob)
    @blob_ids.include?(blob.id) || @keys.include?(blob.key)
  end

  private

  # The segment as written and every level of URL-unescaping, for links that
  # were escaped more than once. Never "+" to space: it is a Base64 character.
  def unescapings(segment)
    [ segment ].tap do |forms|
      forms << URI.decode_uri_component(forms.last) while forms.last.include?("%") && forms.size < 4
    rescue ArgumentError
      # A malformed escape: keep the forms decoded so far.
    end
  end

  # The blob ids inside a signed id or signed global id, in any format Rails
  # has used here:
  #   Rails 7+:     {"_rails":{"data":VALUE,"pur":...}}
  #   Rails 5.2/6:  {"_rails":{"message":Base64(Marshal or JSON of VALUE),...}}
  # where VALUE is a blob id or a "gid://.../ActiveStorage::Blob/ID" string.
  def signed_blob_ids(signed)
    payload = decode64(signed.split("--").first) or return []
    envelope = parse_json(payload)
    envelope = envelope["_rails"] if envelope.is_a?(Hash)
    return blob_ids_in(payload) unless envelope.is_a?(Hash)

    if envelope.key?("data")
      blob_ids_in(envelope["data"])
    elsif (message = decode64(envelope["message"]))
      blob_ids_in(message)
    else
      []
    end
  end

  def blob_ids_in(value)
    case value
    when Integer then [ value ]
    when String
      ids = value.b.scan(BLOB_GLOBAL_ID).flatten.map(&:to_i)
      ids << marshaled_integer(value) << parse_json(value)
      ids.grep(Integer)
    else []
    end
  end

  def decode64(value)
    return unless value.is_a?(String) && value.present?

    Base64.strict_decode64(value)
  rescue ArgumentError
    begin
      Base64.urlsafe_decode64(value)
    rescue ArgumentError
      nil
    end
  end

  def parse_json(value)
    JSON.parse(value)
  rescue JSON::ParserError, EncodingError
    nil
  end

  # Reads the one Marshal type Rails used for blob ids, without Marshal.load.
  def marshaled_integer(bytes)
    bytes = bytes.b
    return unless bytes.start_with?(MARSHAL_INTEGER) && (code = bytes.getbyte(3))

    case code
    when 0 then 0
    when 1..4 then bytes.byteslice(4, code).bytes.each_with_index.sum { |byte, index| byte << (8 * index) }
    when 6..127 then code - 5
    end
  end
end
