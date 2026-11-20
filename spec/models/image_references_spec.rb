require 'rails_helper'

RSpec.describe ImageReferences do
  let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('image'), filename: 'photo.png', content_type: 'image/png') }
  let(:other) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('other'), filename: 'photo.png', content_type: 'image/png') }

  def referenced_by?(html)
    described_class.new.tap { |references| references.add(html) }.include?(blob)
  end

  # Signed ids as Rails 5.2 and 6 made them: a Marshal-serialized id inside
  # a JSON envelope. Signatures are never checked, so any digest will do.
  def envelope_signed_id(id)
    message = Base64.strict_encode64(Marshal.dump(id))
    "#{Base64.strict_encode64({ _rails: { message:, exp: nil, pur: 'blob_id' } }.to_json)}--#{'0' * 40}"
  end

  {
    'a redirect URL' => ->(id) { %(<img src="/rails/active_storage/blobs/redirect/#{id}/photo.png">) },
    'a proxy URL' => ->(id) { %(<img src="/rails/active_storage/blobs/proxy/#{id}/photo.png">) },
    'a pre-6.1 blob URL' => ->(id) { %(<img src="/rails/active_storage/blobs/#{id}/photo.png">) },
    'a representation URL' => ->(id) { %(<img src="/rails/active_storage/representations/redirect/#{id}/variation/photo.png">) },
    'an absolute link' => ->(id) { %(<a href="https://www.easy-rsvp.com/rails/active_storage/blobs/redirect/#{id}/photo.png">photo</a>) },
    'an escaped signed id' => ->(id) { %(<img src="/rails/active_storage/blobs/redirect/#{CGI.escape(id)}/photo.png">) },
    'a twice-escaped signed id' => ->(id) { %(<img src="/rails/active_storage/blobs/redirect/#{CGI.escape(CGI.escape(id))}/photo.png">) },
    'Trix attachment JSON with escaped slashes' =>
      ->(id) { %(<figure data-trix-attachment="{&quot;url&quot;:&quot;https:\\/\\/www.easy-rsvp.com\\/rails\\/active_storage\\/blobs\\/redirect\\/#{id}\\/photo.png&quot;}"></figure>) }
  }.each do |form, html|
    it "finds the blob behind #{form}" do
      expect(referenced_by?(html.call(blob.signed_id))).to be(true)
    end

    it "finds the blob behind #{form} with a Rails 5.2 signed id" do
      expect(referenced_by?(html.call(envelope_signed_id(blob.id)))).to be(true)
    end
  end

  it 'finds Action Text attachments by their sgid, with or without an attachment row' do
    expect(referenced_by?(%(<action-text-attachment sgid="#{blob.attachable_sgid}"></action-text-attachment>))).to be(true)
  end

  it 'finds blob keys, as in direct storage URLs' do
    expect(referenced_by?(%(<img src="https://www.easy-rsvp.com.s3.amazonaws.com/#{blob.key}">))).to be(true)
  end

  it 'finds nothing in unrelated or malformed content' do
    [
      %(<img src="/rails/active_storage/blobs/redirect/#{other.signed_id}/photo.png">),
      '<img src="/rails/active_storage/blobs/redirect/not-base64%ZZ/photo.png">',
      '<img src="/rails/active_storage/blobs/redirect/e30=--abc/photo.png">',
      '<action-text-attachment sgid="garbage"></action-text-attachment>',
      'Bring something to share.',
      nil
    ].each { |html| expect(referenced_by?(html)).to be(false), html.inspect }
  end

  it 'reads the descriptions of the given events only' do
    linked = create(:event, body: %(<img src="/rails/active_storage/blobs/redirect/#{blob.signed_id}/photo.png">))

    expect(described_class.in_descriptions_of(Event.where(id: linked.id)).include?(blob)).to be(true)
    expect(described_class.in_descriptions_of(Event.where.not(id: linked.id)).include?(blob)).to be(false)
  end
end
