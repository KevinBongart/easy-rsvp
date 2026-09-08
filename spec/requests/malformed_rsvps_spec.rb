require 'rails_helper'

RSpec.describe 'Malformed public RSVP requests', type: :request do
  let!(:event) { create(:event) }

  ['', [], ['Yes'], { answer: 'Yes' }].each do |submit|
    it "rejects submit value #{submit.inspect} without saving or claiming ownership" do
      expect do
        post event_rsvps_path(event), params: { rsvp: { name: 'Guest' }, commit: submit }
      end.not_to change(Rsvp, :count)
      expect(response).to have_http_status(submit.is_a?(String) ? :redirect : :bad_request)
      expect(request.session[event.hashid]).to be_nil
    end
  end

  [nil, {}, { response: 'yes' }].each do |attributes|
    it "rejects missing name parameters #{attributes.inspect} without mutation" do
      expect do
        post event_rsvps_path(event), params: { rsvp: attributes, commit: 'Yes' }
      end.not_to change(Rsvp, :count)
      expect(response).to have_http_status(attributes.blank? ? :bad_request : :redirect)
      expect(request.session[event.hashid]).to be_nil
    end
  end

  it 'rejects deletion after this session deleted its last owned response' do
    post event_rsvps_path(event), params: { rsvp: { name: 'Mine' }, commit: 'Yes' }
    delete event_rsvp_path(event, event.rsvps.last)
    other = create(:rsvp, event: event)

    expect { delete event_rsvp_path(event, other) }.not_to change(Rsvp, :count)
    expect(response).to redirect_to(event)
  end

  it 'denies deletion with an explicitly empty ownership list' do
    rsvp = create(:rsvp, event: event)
    cookie_key = Rails.application.config.session_options.fetch(:key)
    get event_path(event)
    jar = request.cookie_jar
    jar.signed_or_encrypted[cookie_key] = { value: { "session_id" => SecureRandom.hex(16), event.hashid => [] } }
    expect(jar.signed_or_encrypted[cookie_key]).to include(event.hashid => [])

    get event_path(event), headers: { 'HTTP_COOKIE' => "#{cookie_key}=#{CGI.escape(jar[cookie_key])}" }
    expect(request.cookie_jar.signed_or_encrypted[cookie_key]).to include(event.hashid => [])
    expect(request.session[event.hashid]).to eq([])
    expect do
      delete event_rsvp_path(event, rsvp), headers: { 'HTTP_COOKIE' => "#{cookie_key}=#{CGI.escape(jar[cookie_key])}" }
    end.not_to change(Rsvp, :count)
    expect(response).to redirect_to(event)
    expect(request.session[event.hashid]).to eq([])
  end

  ['invalid', ['invalid']].each do |attributes|
    it "rejects malformed RSVP attributes #{attributes.inspect}" do
      expect do
        post event_rsvps_path(event), params: { rsvp: attributes, commit: 'Yes' }
      end.not_to change(Rsvp, :count)
      expect(response).to have_http_status(:bad_request)
    end
  end

end
