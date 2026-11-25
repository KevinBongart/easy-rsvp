require 'rails_helper'

RSpec.describe SpamReviewStatus do
  it 'starts blank and healthy before the first review' do
    expect(described_class.current).to have_attributes(new_record?: true, failing?: false, consecutive_failures: 0)
  end

  it 'reports only the failure that starts a streak, and keeps its start' do
    started = Time.zone.local(2026, 11, 20, 12)
    travel_to(started) { expect(described_class.record_failure!('Net::ReadTimeout')).to be(true) }
    travel_to(started + 1.minute) { expect(described_class.record_failure!('SocketError')).to be(false) }

    expect(described_class.current).to have_attributes(
      failing?: true, failing_since: started, consecutive_failures: 2, last_error: 'SocketError', last_failed_at: started + 1.minute
    )
  end

  it 'starts a new streak after a success' do
    described_class.record_failure!('SocketError')
    described_class.record_success!

    expect(described_class.current).to have_attributes(failing?: false, consecutive_failures: 0, last_succeeded_at: be_present)
    expect(described_class.record_failure!('SocketError')).to be(true)
  end

  it 'keeps one row and short error summaries' do
    described_class.record_success!
    described_class.record_failure!('x' * 500)
    described_class.record_success!

    expect(described_class.count).to eq(1)
    expect(described_class.current.last_error.size).to eq(described_class::ERROR_SUMMARY_LENGTH)
  end

  it 'counts events created since the last success that Jev never scored and nobody flagged or decided on' do
    now = Time.zone.local(2026, 11, 20, 12)
    travel_to(now - 90.minutes) { described_class.record_success! }
    travel_to(now - 1.hour) { described_class.record_failure!('SocketError') }
    travel_to now do
      create(:event, created_at: 2.hours.ago)
      create_list(:event, 2, created_at: 80.minutes.ago)
      create(:event).update_columns(spam_score: 0.2)
      create(:event, spam_source: :cleared)
      create(:event, title: 'Best IPTV provider 2026')

      expect(described_class.current.unreviewed_events_count).to eq(2)
    end
  end

  it 'counts from just before the first failure when Jev never answered' do
    travel_to Time.zone.local(2026, 11, 20, 12) do
      create(:event, created_at: 10.minutes.ago)
      create(:event, created_at: 3.minutes.ago)
      described_class.record_failure!('SocketError')

      expect(described_class.current.unreviewed_events_count).to eq(1)
    end
  end

  it 'counts the event whose review failed after a concurrent review succeeded' do
    now = Time.zone.local(2026, 11, 20, 12)
    travel_to(now - 1.hour) { described_class.record_success! }
    timed_out = travel_to(now) { create(:event) }
    travel_to(now) { create(:event).update_columns(spam_score: 0.1) }
    travel_to(now + 3.seconds) { described_class.record_success! }
    travel_to(now + 20.seconds) { described_class.record_failure!('Net::ReadTimeout') }

    expect(described_class.current).to have_attributes(unreviewed_since: now + 20.seconds - 5.minutes, unreviewed_events_count: 1)
    expect(Event.without_spam_review).to contain_exactly(timed_out)
  end

  it 'counts nothing while healthy, including before the first review' do
    create(:event)
    expect(described_class.current).to have_attributes(unreviewed_since: nil, unreviewed_events_count: 0)

    described_class.record_success!
    expect(described_class.current).to have_attributes(unreviewed_since: nil, unreviewed_events_count: 0)
  end
end
