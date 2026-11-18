require 'rails_helper'

RSpec.describe 'Event creation limit', type: :request do
  let(:ip) { '203.0.113.7' }

  def create_event(title: 'Garden party', from: ip)
    post events_path,
      params: { event: { title: title, date: '2026-12-24', body: '<div>Bring a dish</div>' } },
      env: { 'REMOTE_ADDR' => from }
  end

  it 'lets a client create five events within thirty minutes' do
    expect {
      5.times { |n| create_event(title: "Party #{n}") }
    }.to change(Event, :count).by(5)

    expect(response).to have_http_status(:redirect)
  end

  it 'refuses a sixth event with an explanation and keeps the form input' do
    5.times { |n| create_event(title: "Party #{n}") }

    expect { create_event(title: 'One party too many') }.not_to change(Event, :count)

    expect(response).to have_http_status(:too_many_requests)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('#flash_alert').text).to eq(
      "To prevent abuse on Easy RSVP, we're limiting how many events you can create in a short window. " \
      'Please wait 30 minutes and try again.'
    )
    expect(page.at_css('input#event_title')['value']).to eq('One party too many')
  end

  it 'does not count submissions that fail validation' do
    5.times { create_event(title: '') }

    expect { create_event(title: 'Fixed it') }.to change(Event, :count).by(1)
  end

  it 'counts each client separately' do
    5.times { |n| create_event(title: "Party #{n}") }

    expect { create_event(title: 'Someone else', from: '198.51.100.20') }.to change(Event, :count).by(1)
  end

  it 'treats addresses in the same IPv6 /64 as one client' do
    5.times { |n| create_event(title: "Party #{n}", from: "2001:db8:1:2::#{n + 1}") }

    expect { create_event(from: '2001:db8:1:2:ffff::9') }.not_to change(Event, :count)
    expect { create_event(from: '2001:db8:1:3::1') }.to change(Event, :count).by(1)
  end

  it 'allows creating events again once the window has passed' do
    travel_to(Time.zone.local(2026, 11, 18, 12, 0)) do
      5.times { |n| create_event(title: "Party #{n}") }
    end

    travel_to(Time.zone.local(2026, 11, 18, 12, 29)) do
      expect { create_event }.not_to change(Event, :count)
    end

    travel_to(Time.zone.local(2026, 11, 18, 12, 31)) do
      expect { create_event }.to change(Event, :count).by(1)
    end
  end

  it 'stores neither the address nor a link to the event' do
    create_event

    record = RecentEventCreation.sole
    expect(RecentEventCreation.column_names).to contain_exactly('id', 'client_digest', 'created_at')
    expect(record.client_digest).to match(/\A\h{64}\z/)
    expect(record.client_digest).not_to include(ip)
    expect(Event.column_names.grep(/ip|digest/)).to be_empty
  end

  it 'ignores expired counters even before they are cleaned up' do
    travel_to(Time.zone.local(2026, 11, 18, 12, 0)) do
      5.times { RecentEventCreation.create!(client_digest: RecentEventCreation.digest_for(ip)) }
    end

    travel_to(Time.zone.local(2026, 11, 18, 12, 31)) do
      allow(RecentEventCreation).to receive(:where).and_call_original
      allow(RecentEventCreation).to receive(:where).with(created_at: anything).and_return(RecentEventCreation.none)

      expect { create_event }.to change(Event, :count).by(1)
    end
  end

  it 'deletes counters that fall outside the window' do
    travel_to(Time.zone.local(2026, 11, 18, 12, 0)) { create_event(from: '198.51.100.1') }

    travel_to(Time.zone.local(2026, 11, 18, 13, 0)) { create_event(from: '198.51.100.2') }

    expect(RecentEventCreation.count).to eq(1)
  end
end
