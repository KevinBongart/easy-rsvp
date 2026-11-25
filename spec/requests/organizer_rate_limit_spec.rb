require 'rails_helper'

RSpec.describe 'Organizer rate limit', type: :request do
  let(:event) { create(:event) }
  let(:ip) { '203.0.113.7' }
  let(:limit) { OrganizerEventsController::BURST_LIMIT }

  def save(title, from: ip)
    patch event_admin_path(event, event.admin_token), params: { event: { title: } }, env: { 'REMOTE_ADDR' => from }
  end

  it 'accepts saves up to the limit and refuses the next with a neutral 429 page' do
    limit.times { |n| save("Garden party #{n}") }
    expect(event.reload.title).to eq("Garden party #{limit - 1}")

    expect { save('One more') }.not_to have_enqueued_job(EventSpamReviewJob)

    expect(response).to have_http_status(:too_many_requests)
    expect(event.reload.title).to eq("Garden party #{limit - 1}")
    expect(Nokogiri::HTML(response.body).at_css('main p').text).to eq(OrganizerEventsController::LIMITED_MESSAGE)
  end

  it 'counts publish toggles with saves, and each client separately' do
    limit.times { save('Garden party') }

    post toggle_publish_event_admin_path(event, event.admin_token), env: { 'REMOTE_ADDR' => ip }
    expect(response).to have_http_status(:too_many_requests)
    expect(event.reload).to be_published

    save('Potluck', from: '198.51.100.20')
    expect(event.reload.title).to eq('Potluck')
  end

  it 'caps saves per day once the burst windows pass' do
    start = Time.zone.local(2026, 11, 20, 12, 0)
    per_window = OrganizerEventsController::DAILY_LIMIT / 4
    4.times do |window|
      travel_to(start + (window * 11).minutes) { per_window.times { save('Garden party') } }
    end

    travel_to(start + 1.hour) do
      save('One more')
      expect(response).to have_http_status(:too_many_requests)
    end
    travel_to(start + 1.day + 1.minute) do
      save('Next day')
      expect(event.reload.title).to eq('Next day')
    end
  end

  it 'leaves viewing the organizer page unlimited' do
    limit.times { save('Garden party') }

    get event_admin_path(event, event.admin_token), env: { 'REMOTE_ADDR' => ip }

    expect(response).to have_http_status(:ok)
  end
end
