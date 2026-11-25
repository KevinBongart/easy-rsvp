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
      'Please try again later.'
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

  it 'links the counter to the event but never stores the address' do
    create_event

    record = RecentEventCreation.sole
    expect(RecentEventCreation.column_names).to contain_exactly('id', 'client_digest', 'created_at', 'event_id', 'spam_at')
    expect(record.event).to eq(Event.sole)
    expect(record.client_digest).to match(/\A\h{64}\z/)
    expect(record.client_digest).not_to include(ip)
    expect(Event.column_names.grep(/ip|digest/)).to be_empty
  end

  it 'ignores counters outside the window that are still kept for the spam block' do
    travel_to(Time.zone.local(2026, 11, 18, 12, 0)) do
      5.times { |n| create_event(title: "Party #{n}") }
    end

    travel_to(Time.zone.local(2026, 11, 18, 12, 31)) do
      expect { create_event }.to change(Event, :count).by(1)
      expect(RecentEventCreation.count).to eq(6)
    end
  end

  it 'deletes counters, and their links to events, once older than the spam block' do
    travel_to(Time.zone.local(2026, 11, 18, 12, 0)) { create_event(from: '198.51.100.1') }
    travel_to(Time.zone.local(2026, 11, 18, 13, 59)) { create_event(from: '198.51.100.2') }
    expect(RecentEventCreation.count).to eq(2)

    travel_to(Time.zone.local(2026, 11, 18, 14, 1)) { create_event(from: '198.51.100.3') }

    expect(RecentEventCreation.count).to eq(2)
    expect(RecentEventCreation.pluck(:event_id)).not_to include(Event.order(:id).first.id)
  end

  describe 'clients behind spam' do
    let(:spam_title) { 'Buy Xanax Online No Rx' }

    # The background review scoring the event as spam, through the real job.
    def flag_later(event)
      previous = ENV['TYPESAFE_API_KEY']
      ENV['TYPESAFE_API_KEY'] = 'test-key'
      stub_request(:post, 'https://api.typesafe.ai/v1/systemone')
        .to_return(status: 200, body: { answers: { advertising: { noul: 0.99 } } }.to_json)
      EventSpamReviewJob.perform_now(event.id)
      expect(event.reload).to be_flagged_as_spam
    ensure
      ENV['TYPESAFE_API_KEY'] = previous
    end

    it 'refuses the next event after one flagged at creation, with the same message' do
      create_event(title: spam_title)
      expect(Event.sole).to be_spam

      expect { create_event(title: 'Garden party') }.not_to change(Event, :count)

      expect(response).to have_http_status(:too_many_requests)
      expect(Nokogiri::HTML(response.body).at_css('#flash_alert').text)
        .to eq(EventsController::CREATION_LIMITED_MESSAGE)
    end

    it 'does not count refused attempts as creations' do
      create_event(title: spam_title)
      3.times { create_event(title: 'Garden party') }

      expect(RecentEventCreation.count).to eq(1)
    end

    it 'refuses the next event after a flag set by the background review' do
      create_event
      flag_later(Event.sole)

      expect { create_event(title: 'Another party') }.not_to change(Event, :count)
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'counts operator marks too' do
      create_event
      post mark_spam_admin_event_path(Event.sole), headers: dashboard_headers

      expect { create_event(title: 'Another party') }.not_to change(Event, :count)
    end

    it 'does not block a different client' do
      create_event(title: spam_title)

      expect { create_event(from: '198.51.100.20') }.to change(Event, :count).by(1)
    end

    it 'blocks the whole IPv6 /64 and nothing outside it' do
      create_event(title: spam_title, from: '2001:db8:1:2::1')

      expect { create_event(from: '2001:db8:1:2:ffff::9') }.not_to change(Event, :count)
      expect { create_event(from: '2001:db8:1:3::1') }.to change(Event, :count).by(1)
    end

    it 'lifts the block two hours after the flagged event was created' do
      travel_to(Time.zone.local(2026, 11, 18, 12, 0)) { create_event(title: spam_title) }

      travel_to(Time.zone.local(2026, 11, 18, 13, 59)) do
        expect { create_event }.not_to change(Event, :count)
      end

      travel_to(Time.zone.local(2026, 11, 18, 14, 1)) do
        expect { create_event }.to change(Event, :count).by(1)
      end
    end

    it 'keeps the block when the organizer edits the flag away' do
      create_event(title: spam_title)
      event = Event.sole

      patch event_admin_path(event, event.admin_token), params: { event: { title: 'Lab holiday dinner' } }
      expect(event.reload).not_to be_spam

      expect { create_event }.not_to change(Event, :count)
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'keeps the block after a background flag is edited away' do
      create_event
      event = Event.sole
      flag_later(event)

      patch event_admin_path(event, event.admin_token), params: { event: { title: 'Party at noon' } }
      expect(event.reload).not_to be_spam

      expect { create_event(title: 'Another party') }.not_to change(Event, :count)
    end

    it 'keeps the block when the organizer deletes the flagged event' do
      create_event(title: spam_title)
      event = Event.sole

      expect { delete event_admin_path(event, event.admin_token) }.to change(Event, :count).by(-1)

      expect { create_event }.not_to change(Event, :count)
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'records a flag the Ruby rules set when an existing event is edited into spam' do
      create_event
      event = Event.sole
      patch event_admin_path(event, event.admin_token), params: { event: { title: spam_title } }
      expect(event.reload).to be_spam

      expect { create_event(title: 'Another party') }.not_to change(Event, :count)
    end

    it 'lifts the block when an operator clears the event' do
      create_event(title: spam_title)
      post mark_not_spam_admin_event_path(Event.sole), headers: dashboard_headers

      expect { create_event }.to change(Event, :count).by(1)
    end

    it 'ignores flagged rows older than two hours even before cleanup removes them' do
      create_event(title: spam_title)
      RecentEventCreation.update_all(created_at: 2.hours.ago - 1.minute)
      allow(RecentEventCreation).to receive(:where).and_call_original
      allow(RecentEventCreation).to receive(:where).with(created_at: anything).and_return(RecentEventCreation.none)

      expect { create_event }.to change(Event, :count).by(1)
      expect(RecentEventCreation.where(spam_at: ..Time.current).count).to eq(1)
    end

    it 'keeps working when the organizer deletes an event' do
      travel 1.minute
      4.times { |n| create_event(title: "Party #{n}") }
      event = Event.order(:id).first

      expect { delete event_admin_path(event, event.admin_token) }.to change(Event, :count).by(-1)

      expect(RecentEventCreation.count).to eq(4)
      expect(RecentEventCreation.where(event_id: nil).count).to eq(1)
      expect { create_event(title: 'Fifth') }.to change(Event, :count).by(1)
      expect { create_event(title: 'Sixth') }.not_to change(Event, :count)
    end
  end
end
