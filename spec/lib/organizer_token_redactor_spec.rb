require 'rails_helper'

RSpec.describe OrganizerTokenRedactor do
  let(:token) { SecureRandom.uuid }

  it 'redacts paths, standalone SQL values, referers and encoded path segments' do
    examples = ["Started GET /party/admin/#{token}/edit", "admin_token=#{token}",
                "https://example.com/party/admin/#{token}?sort=recent", "/party/admin/#{token.gsub('-', '%2D')}/rsvps/1",
                '/party/admin/%30%31%32%33/edit']
    examples.each do |text|
      expect(described_class.redact(text)).to include('[FILTERED]')
      expect(described_class.redact(text).include?(token)).to be(false)
    end
    expect(described_class.redact('/admin/events?sort=rsvps')).to eq('/admin/events?sort=rsvps')
    expect(described_class.redact('/party')).to eq('/party')
  end

  it 'scrubs nested Rollbar payloads without losing diagnostic metadata' do
    payload = { 'data' => { 'request' => { 'url' => "https://example.com/party/admin/#{token}" },
                           'body' => { 'message' => { 'body' => "Failed #{token}" } }, 'level' => 'error' } }
    Rollbar.configuration.transform.each { |transform| transform.call(payload) }
    expect(payload.to_s.include?(token)).to be(false)
    expect(payload.dig('data', 'level')).to eq('error')
  end

  it 'preserves tagged logger behavior while filtering tags and messages' do
    output = StringIO.new
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(output))
    logger.formatter = described_class::Formatter.new(logger.formatter)
    logger.tagged(token) { logger.info("Organizer #{token}") }
    expect(output.string.include?(token)).to be(false)
    expect(output.string).to include('Organizer [FILTERED]')
  end
end
