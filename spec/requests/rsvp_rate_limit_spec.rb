require 'rails_helper'

RSpec.describe 'RSVP rate limit', type: :request do
  let(:event) { create(:event) }
  let(:ip) { '203.0.113.7' }
  let(:limit) { RsvpsController::WRITE_LIMIT }

  def respond(name: 'Guest', from: ip)
    post event_rsvps_path(event), params: { rsvp: { name: name }, commit: 'Yes' }, env: { 'REMOTE_ADDR' => from }
  end

  it 'accepts responses up to the limit and refuses the next with a neutral 429 page' do
    expect { limit.times { |n| respond(name: "Guest #{n}") } }.to change(Rsvp, :count).by(limit)

    expect { respond }.not_to change(Rsvp, :count)

    expect(response).to have_http_status(:too_many_requests)
    expect(Nokogiri::HTML(response.body).at_css('main p').text).to eq(RsvpsController::LIMITED_MESSAGE)
  end

  it 'counts deletions with responses' do
    rsvp = create(:rsvp, event:)
    limit.times { respond }

    delete event_rsvp_path(event, rsvp), env: { 'REMOTE_ADDR' => ip }

    expect(response).to have_http_status(:too_many_requests)
    expect(Rsvp.exists?(rsvp.id)).to be(true)
  end

  it 'counts each client separately' do
    limit.times { respond }

    expect { respond(from: '198.51.100.20') }.to change(Rsvp, :count).by(1)
  end

  it 'counts an IPv6 /64 as one client' do
    limit.times { |n| respond(from: "2001:db8:1:2::#{n.to_s(16)}") }

    expect { respond(from: '2001:db8:1:2:ffff::1') }.not_to change(Rsvp, :count)
    expect(response).to have_http_status(:too_many_requests)
    expect { respond(from: '2001:db8:1:3::1') }.to change(Rsvp, :count).by(1)
  end

  it 'accepts responses again once the window has passed' do
    travel_to(Time.zone.local(2026, 11, 20, 12, 0)) { limit.times { respond } }

    travel_to(Time.zone.local(2026, 11, 20, 12, 9)) do
      expect { respond }.not_to change(Rsvp, :count)
    end
    travel_to(Time.zone.local(2026, 11, 20, 12, 10, 1)) do
      expect { respond }.to change(Rsvp, :count).by(1)
    end
  end

  it 'leaves organizer RSVP management unlimited' do
    rsvp = create(:rsvp, event:)
    limit.times { respond }

    patch event_admin_rsvp_path(event, event.admin_token, rsvp),
      params: { rsvp: { name: 'Renamed', response: 'maybe' } }, env: { 'REMOTE_ADDR' => ip }

    expect(rsvp.reload.name).to eq('Renamed')
  end
end
