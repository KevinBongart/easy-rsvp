require 'rails_helper'

RSpec.describe Event, 'length and image limits', type: :model do
  def blob(size)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('x'), filename: 'photo.png', content_type: 'image/png')
      .tap { |created| created.update_columns(byte_size: size) }
  end

  def embed(*blobs)
    blobs.map { |embedded| %(<action-text-attachment sgid="#{embedded.attachable_sgid}"></action-text-attachment>) }.join
  end

  def legacy_image(url, size)
    attributes = CGI.escapeHTML({ contentType: 'image/png', filesize: size, url: url }.to_json)
    %(<figure data-trix-attachment="#{attributes}"><img src="#{url}"></figure>)
  end

  def text(length)
    "<div>#{'a' * length}</div>"
  end

  describe 'title' do
    it 'accepts 200 characters and rejects 201' do
      expect(build(:event, title: 'a' * 200)).to be_valid

      event = build(:event, title: 'a' * 201)
      expect(event).not_to be_valid
      expect(event.errors[:title]).to include('is too long (maximum is 200 characters)')
    end

    it 'keeps an existing long title editable for other fields' do
      event = create(:event)
      event.update_column(:title, 'a' * 300)

      expect(event.reload.update(date: event.date + 1.day, body: text(10))).to be(true)
      expect(event.update(title: 'b' * 250)).to be(true)
      expect(event.update(title: 'b' * 251)).to be(false)
      expect(event.errors[:title]).to include('is too long (maximum is 200 characters)')
    end
  end

  describe 'description length' do
    it 'counts visible text up to 20,000 characters' do
      expect(build(:event, body: text(20_000))).to be_valid

      event = build(:event, body: text(20_001))
      expect(event).not_to be_valid
      expect(event.errors[:body].first).to start_with('The description can be at most 20,000 characters of text')
    end

    it 'ignores markup and inline image payloads' do
      body = %(<div><strong>#{'a' * 19_000}</strong></div><img src="data:image/png;base64,#{'A' * 50_000}">)

      expect(build(:event, body: body)).to be_valid
    end

    it 'counts text in captions and pasted content attachments' do
      pasted = %(<action-text-attachment content-type="text/html" content="#{CGI.escapeHTML(text(20_001))}"></action-text-attachment>)

      expect(build(:event, body: pasted)).not_to be_valid
    end

    it 'keeps an existing long description editable' do
      event = create(:event)
      event.rich_text_body.update_column(:body, text(30_000))
      event = described_class.find(event.id)

      expect(event.update(title: 'New title')).to be(true)
      expect(event.update(body: text(29_000))).to be(true)
      expect(event.update(body: text(29_500))).to be(false)
    end
  end

  describe 'embedded images' do
    it 'allows up to 10 MB of images in the description' do
      expect(build(:event, body: embed(blob(5.megabytes), blob(5.megabytes)))).to be_valid
    end

    it 'rejects more than 10 MB with a visible message' do
      event = build(:event, body: embed(blob(5.megabytes), blob(5.megabytes), blob(1)))

      expect(event).not_to be_valid
      expect(event.errors[:body]).to include('Images in the description can add up to 10 MB; remove some and try again.')
    end

    it 'counts an image embedded twice once' do
      shared = blob(6.megabytes)

      expect(build(:event, body: embed(shared, shared))).to be_valid
    end

    it 'counts images referenced by Active Storage URL by their stored size, never the submitted one' do
      first, second = blob(6.megabytes), blob(6.megabytes)
      body = legacy_image("/rails/active_storage/blobs/redirect/#{first.signed_id}/a.png", 0) +
             legacy_image("/rails/active_storage/blobs/#{second.signed_id}/b.png", 1)

      expect(build(:event, body: body)).not_to be_valid
      expect(build(:event, body: legacy_image('/rails/active_storage/blobs/redirect/forged/a.png', 50.megabytes))).to be_valid
      expect(build(:event, body: legacy_image('https://example.com/a.png', 50.megabytes))).to be_valid
    end

    it 'counts a blob once whether it is embedded or referenced by URL' do
      shared = blob(6.megabytes)
      body = embed(shared) + legacy_image("/rails/active_storage/blobs/redirect/#{shared.signed_id}/a.png", 0)

      expect(build(:event, body: body)).to be_valid
    end

    it 'keeps an event already over the limit editable unless images are added' do
      large = [ blob(6.megabytes), blob(6.megabytes) ]
      event = create(:event)
      event.rich_text_body.update_column(:body, embed(*large))
      event = described_class.find(event.id)

      expect(event.update(title: 'New title')).to be(true)
      expect(event.update(body: "#{embed(*large)}<div>Updated details</div>")).to be(true)
      expect(event.update(body: embed(*large, blob(1)))).to be(false)
      expect(event.errors[:body]).to include(described_class::IMAGES_TOO_LARGE)
    end
  end
end
