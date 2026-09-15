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

  it 'scrubs Honeybadger notice URLs and diagnostic data without sending it' do
    notice_class = Struct.new(*described_class::HONEYBADGER_NOTICE_FIELDS, keyword_init: true)
    notice = notice_class.new(
      url: "https://example.com/party/admin/#{token}",
      error_message: "Failed #{token}",
      context: { event: token },
      params: { admin_token: token },
      details: { safe: 'kept' }
    )

    Honeybadger.config.before_notify_hooks.each { |hook| hook.call(notice) }

    expect(notice.to_h.to_s).not_to include(token)
    expect(notice.url).to eq('https://example.com/party/admin/[FILTERED]')
    expect(notice.details).to eq({ safe: 'kept' })
  end

  it 'keeps sessions and Insights out of Honeybadger reports' do
    expect(Honeybadger.config.public?).to be(false)
    expect(Honeybadger.config.get(:'request.disable_session')).to be(true)
    expect(Honeybadger.config.get(:'insights.enabled')).to be(false)
    expect(Honeybadger.config.get(:'request.filter_keys')).to include('admin_token', 'password', 'email', 'cookie')
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
