require 'rails_helper'

RSpec.describe 'Framework-default compatibility', type: :request do
  def legacy_key_generator
    ActiveSupport::CachingKeyGenerator.new(
      ActiveSupport::KeyGenerator.new(
        Rails.application.secret_key_base,
        iterations: 1000,
        hash_digest_class: OpenSSL::Digest::SHA1
      )
    )
  end

  def legacy_session_cookie(session_data)
    env = Rack::MockRequest.env_for('/')
    Rails.application.env_config.each { |key, value| env[key] = value }
    cookie_request = ActionDispatch::Request.new(env)
    cookie_request.set_header('action_dispatch.key_generator', legacy_key_generator)
    jar = ActionDispatch::Cookies::CookieJar.build(cookie_request, {})
    session_key = Rails.application.config.session_options.fetch(:key)
    jar.encrypted[session_key] = {
      value: session_data.merge('session_id' => SecureRandom.hex(16))
    }
    jar.to_header
  end

  it 'reads an RSVP ownership session whose key was derived with the old SHA-1 default' do
    event = create(:event)
    rsvp = create(:rsvp, event: event)
    cookie = legacy_session_cookie(event.hashid => [rsvp.hashid])

    expect do
      delete event_rsvp_path(event, rsvp), headers: { 'Cookie' => cookie }
    end.to change(Rsvp, :count).by(-1)
  end

  it 'resolves an Action Text attachment stored with the old signed Global ID format' do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('legacy attachment'),
      filename: 'legacy.txt',
      content_type: 'text/plain'
    )
    verifier = GlobalID::Verifier.new(
      legacy_key_generator.generate_key('signed_global_ids'),
      serializer: :marshal,
      force_legacy_metadata_serializer: true
    )
    sgid = blob.to_sgid(
      expires_in: nil,
      for: ActionText::Attachable::LOCATOR_NAME,
      verifier: verifier
    ).to_s
    persisted_content = ActionText::Content.new(
      %(<action-text-attachment sgid="#{sgid}"></action-text-attachment>)
    )

    expect(persisted_content.attachables).to contain_exactly(blob)
  end
end
