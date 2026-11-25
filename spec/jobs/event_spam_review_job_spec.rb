require 'rails_helper'

RSpec.describe EventSpamReviewJob do
  around do |example|
    previous = ENV['TYPESAFE_API_KEY']
    ENV['TYPESAFE_API_KEY'] = 'test-key'
    example.run
  ensure
    ENV['TYPESAFE_API_KEY'] = previous
  end

  def stub_jev(score)
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone')
      .to_return(status: 200, body: { answers: { advertising: { noul: score } } }.to_json)
  end

  it 'is queued after an event the Ruby rules pass is saved, and again after edits' do
    event = nil
    expect { event = create(:event, title: 'Garden party') }.to have_enqueued_job(described_class).with(kind_of(Integer))
    expect { event.update!(title: 'Garden party at noon') }.to have_enqueued_job(described_class).with(event.id)
    expect { event.update!(body: '<div>Bring a chair</div>') }.to have_enqueued_job(described_class).with(event.id)
    expect { event.update!(published: false) }.not_to have_enqueued_job(described_class)
  end

  it 'does not queue a review for an unrelated save after a rolled-back one' do
    event = create(:event)
    Event.transaction do
      event.update!(title: 'Renamed')
      raise ActiveRecord::Rollback
    end

    expect { event.reload.update!(published: false) }.not_to have_enqueued_job(described_class)
  end

  it 'is not queued for events the Ruby rules flag, or that an admin decided on' do
    expect { create(:event, title: 'Best IPTV provider 2026') }.not_to have_enqueued_job(described_class)

    cleared = create(:event, spam_source: 'cleared')
    expect { cleared.update!(title: 'Changed') }.not_to have_enqueued_job(described_class)
  end

  it 'is not queued without an API key' do
    ENV['TYPESAFE_API_KEY'] = nil
    expect { create(:event) }.not_to have_enqueued_job(described_class)
  end

  it 'flags the event automatically at or above the threshold' do
    event = create(:event)
    stub_jev(0.93)

    described_class.perform_now(event.id)

    expect(event.reload).to have_attributes(spam_source: 'automatic', spam_at: be_present, spam_score: 0.93)
  end

  it 'records the score and leaves the event up below the threshold' do
    event = create(:event)
    stub_jev(0.42)

    described_class.perform_now(event.id)

    expect(event.reload).to have_attributes(spam_source: nil, spam_at: nil, spam_score: 0.42)
  end

  it 'asks Jev once for reviews queued behind several edits, and again once the text changes' do
    event = create(:event)
    stub_jev(0.1)
    3.times { |n| event.update!(title: "Garden party #{n}") }

    3.times { described_class.perform_now(event.id) }
    expect(a_request(:post, 'https://api.typesafe.ai/v1/systemone')).to have_been_made.once

    event.update!(date: event.date + 1)
    described_class.perform_now(event.id)
    expect(a_request(:post, 'https://api.typesafe.ai/v1/systemone')).to have_been_made.once

    event.reload.update!(body: '<div>Bring a chair</div>')
    described_class.perform_now(event.id)
    expect(a_request(:post, 'https://api.typesafe.ai/v1/systemone')).to have_been_made.twice
  end

  it 'reviews new text even when a review of the old text finished after the edit form loaded' do
    event = create(:event)
    loaded_by_edit_request = Event.find(event.id)
    stub_jev(0.1)
    described_class.perform_now(event.id)

    expect { loaded_by_edit_request.update!(title: 'Best deals online') }.to have_enqueued_job(described_class)
    expect(event.reload.spam_score).to be_nil

    stub_jev(0.95)
    described_class.perform_now(event.id)
    expect(event.reload).to have_attributes(spam_source: 'automatic', spam_score: 0.95)
  end

  it 'leaves the event up when TypeSafe fails' do
    event = create(:event)
    allow(Rails.error).to receive(:report)
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return(status: 500)

    described_class.perform_now(event.id)

    expect(event.reload).to have_attributes(spam_source: nil, spam_at: nil, spam_score: nil)
    expect(SpamReviewStatus.current).to have_attributes(failing?: true, unreviewed_events_count: 1)
  end

  it 'leaves the event up and reports when its page cannot be prepared' do
    event = create(:event)
    allow(Rails.error).to receive(:report)
    review = instance_double(Event::SpamReview)
    allow(review).to receive(:page).and_raise(Regexp::TimeoutError)
    allow(Event::SpamReview).to receive(:new).with(event).and_return(review)

    described_class.perform_now(event.id)

    expect(Rails.error).to have_received(:report).with(kind_of(Regexp::TimeoutError), hash_including(handled: true))
    expect(event.reload).to have_attributes(spam_source: nil, spam_score: nil)
  end

  it 'discards its answer when the admin decided while Jev was answering' do
    event = create(:event)
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do
      event.update_columns(spam_source: 'cleared', spam_decided_at: Time.current)
      { status: 200, body: { answers: { advertising: { noul: 0.99 } } }.to_json }
    end

    described_class.perform_now(event.id)

    expect(event.reload).to have_attributes(spam_source: 'cleared', spam_at: nil, spam_score: nil)
  end

  it 'keeps its answer when the organizer changes something other than the text meanwhile' do
    event = create(:event)
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do
      travel(1.second) { Event.find(event.id).toggle!(:published) }
      { status: 200, body: { answers: { advertising: { noul: 0.99 } } }.to_json }
    end

    described_class.perform_now(event.id)

    expect(event.reload).to have_attributes(spam_source: 'automatic', spam_score: 0.99)
  end

  it 'discards its answer when the organizer edited the description meanwhile' do
    event = create(:event)
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do
      travel(1.second) { Event.find(event.id).update!(body: '<div>New plan: we meet at noon</div>') }
      { status: 200, body: { answers: { advertising: { noul: 0.99 } } }.to_json }
    end

    described_class.perform_now(event.id)

    expect(event.reload).to have_attributes(spam_source: nil, spam_score: nil)
  end

  it 'lets the organizer clear a flag by editing, then reviews the new text' do
    event = create(:event)
    stub_jev(0.95)
    described_class.perform_now(event.id)

    expect { event.reload.update!(title: 'Potluck at our place') }.to have_enqueued_job(described_class).with(event.id)
    expect(event.reload).to have_attributes(spam_source: nil, spam_at: nil, spam_score: nil)
  end
end
