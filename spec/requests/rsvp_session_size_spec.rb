require 'rails_helper'

# RSVP ownership used to add one session key per event, so a guest who had
# answered about 100 events hit CookieOverflow after the RSVP was saved.
RSpec.describe 'RSVP ownership in the session cookie', type: :request do
  let(:cookie_key) { Rails.application.config.session_options.fetch(:key) }

  def rsvp_to(event, name: 'Guest')
    post event_rsvps_path(event), params: { rsvp: { name: name }, commit: 'Yes' }
    expect(response).to redirect_to(event)
    event.rsvps.last
  end

  def session_cookie_size
    header = Array(response.headers['Set-Cookie']).join("\n")
    header.lines.map(&:chomp).find { |cookie| cookie.start_with?("#{cookie_key}=") }.split(';').first.bytesize
  end

  def legacy_session_cookie(session_data)
    get root_path
    jar = request.cookie_jar
    jar.signed_or_encrypted[cookie_key] = { value: session_data.merge('session_id' => SecureRandom.hex(16)) }
    "#{cookie_key}=#{CGI.escape(jar[cookie_key])}"
  end

  it "keeps only the #{OwnedRsvps::LIMIT} most recent RSVPs, so answering one more event never overflows" do
    events = create_list(:event, OwnedRsvps::LIMIT + 1)
    rsvps = events.map { |event| rsvp_to(event) }

    expect(owned_rsvp_hashids).to eq(rsvps.drop(1).map(&:hashid))
    expect { delete event_rsvp_path(events.first, rsvps.first) }.not_to change(Rsvp, :count)
    expect { delete event_rsvp_path(events.last, rsvps.last) }.to change(Rsvp, :count).by(-1)
  end

  it 'keeps delete rights from sessions written in the old one-key-per-event format' do
    first_event, second_event = create_list(:event, 2)
    first = create(:rsvp, event: first_event, name: 'First guest')
    second = create(:rsvp, event: second_event, name: 'Second guest')
    cookie = legacy_session_cookie(first_event.hashid => [ first.hashid ], second_event.hashid => [ second.hashid ])

    get event_path(second_event), headers: { 'HTTP_COOKIE' => cookie }
    expect(response.body).to include('Delete RSVP for Second guest')
    expect(session[second_event.hashid]).to be_nil
    expect(owned_rsvp_hashids).to eq([ first.hashid, second.hashid ])

    expect { delete event_rsvp_path(first_event, first) }.to change(Rsvp, :count).by(-1)
    expect(owned_rsvp_hashids).to eq([ second.hashid ])
  end

  context 'with ids long enough for 8-character hashids (production RSVP ids give 7 today)' do
    # setval is not rolled back with the test transaction, so restore it.
    around do |example|
      connection = ActiveRecord::Base.connection
      saved = %w[events_id_seq rsvps_id_seq].index_with do |sequence|
        connection.select_one("SELECT last_value, is_called FROM #{sequence}").values
      end
      saved.each_key { |sequence| connection.select_value("SELECT setval('#{sequence}', 10000000)") }
      example.run
    ensure
      saved&.each { |sequence, (value, called)| connection.select_value("SELECT setval('#{sequence}', #{value}, #{called})") }
    end

    it 'stays well under the 4 KB cookie limit for an organizer who is also a frequent guest' do
      create_list(:event, ManagedEvents::LIMIT).each { |event| get event_admin_path(event, event.admin_token) }
      create_list(:event, OwnedRsvps::LIMIT).each { |event| rsvp_to(event) }
      expect(session[ManagedEvents::SESSION_KEY].size).to eq(ManagedEvents::LIMIT)
      expect(owned_rsvp_hashids.size).to eq(OwnedRsvps::LIMIT)

      expect(owned_rsvp_hashids).to all(have_attributes(size: 8))

      # The last response also carries the flash and the CSRF token.
      get event_path(Event.last)
      rsvp_to(Event.last, name: 'One more guest')
      expect(session_cookie_size).to be < 3_500
    end
  end
end
