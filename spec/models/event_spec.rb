require 'rails_helper'

RSpec.describe Event, type: :model do
  it 'builds a valid event without seed data' do
    expect(build(:event)).to be_valid
  end

  [ :title, :date, :published ].each do |attribute|
    it "requires #{attribute}" do
      event = build(:event, attribute => nil)
      expect(event).not_to be_valid
      expect(event.errors[attribute]).to be_present
    end
  end

  it 'allows an empty description' do
    expect(build(:event, body: nil)).to be_valid
  end

  it 'allows an event to remain date-only' do
    event = build(:event)

    expect(event).to be_valid
    expect(event).not_to be_timed
  end

  it 'stores a complete timed schedule in the selected time zone' do
    event = build(
      :event,
      date: Date.new(2026, 10, 10),
      start_time: '18:00',
      end_time: '21:30',
      time_zone: 'Europe/Paris'
    )

    expect(event).to be_valid
    expect(event.starts_at).to eq(Time.utc(2026, 10, 10, 16, 0))
    expect(event.ends_at).to eq(Time.utc(2026, 10, 10, 19, 30))
  end

  it 'requires both a start and end time for a timed event' do
    event = build(:event, start_time: '18:00', end_time: '', time_zone: 'Europe/Paris')

    expect(event).not_to be_valid
    expect(event.errors.added?(:end_time, :blank)).to be(true)
  end

  it 'treats blank start and end fields as a date-only event' do
    event = build(:event, start_time: '', end_time: '', time_zone: 'Europe/Paris')

    expect(event).to be_valid
    expect(event).to have_attributes(starts_at: nil, ends_at: nil, time_zone: nil)
  end

  it 'accepts a bare hour as that hour in the evening' do
    event = build(
      :event,
      date: Date.new(2026, 10, 10),
      start_time: '7',
      end_time: '10',
      time_zone: 'Europe/Paris'
    )

    expect(event).to be_valid
    expect(event.starts_at).to eq(Time.utc(2026, 10, 10, 17, 0))
    expect(event.ends_at).to eq(Time.utc(2026, 10, 10, 20, 0))
  end

  it 'accepts explicit morning times' do
    event = build(
      :event,
      date: Date.new(2026, 10, 10),
      start_time: '7 am',
      end_time: '10:30 AM',
      time_zone: 'Europe/Paris'
    )

    expect(event).to be_valid
    expect(event.starts_at).to eq(Time.utc(2026, 10, 10, 5, 0))
    expect(event.ends_at).to eq(Time.utc(2026, 10, 10, 8, 30))
  end

  it 'keeps zero-padded input in 24-hour time' do
    event = build(
      :event,
      date: Date.new(2026, 10, 10),
      start_time: '09:00',
      end_time: '11:00 AM',
      time_zone: 'Europe/Paris'
    )

    expect(event).to be_valid
    expect(event.starts_at).to eq(Time.utc(2026, 10, 10, 7, 0))
    expect(event.ends_at).to eq(Time.utc(2026, 10, 10, 9, 0))
  end

  it 'requires the end time to be after the start time' do
    event = build(:event, start_time: '18:00', end_time: '17:00', time_zone: 'Europe/Paris')

    expect(event).not_to be_valid
    expect(event.errors[:end_time]).to include('must be after the start time')
  end

  it 'requires a recognized time zone for a timed event' do
    event = build(
      :event,
      start_time: '18:00',
      end_time: '21:00',
      time_zone: 'Central Time (US & Canada)'
    )

    expect(event).not_to be_valid
    expect(event.errors[:time_zone]).to include("isn't recognized")
  end

  it 'requires a time zone for a timed event' do
    event = build(:event, start_time: '18:00', end_time: '21:00', time_zone: '')

    expect(event).not_to be_valid
    expect(event.errors[:time_zone]).to include("can't be blank")
  end

  it 'can return a timed event to a date-only event' do
    event = create(:event, :timed)

    expect(event.update(start_time: '', end_time: '', time_zone: 'Europe/Paris')).to be(true)
    expect(event.reload).to have_attributes(starts_at: nil, ends_at: nil, time_zone: nil)
  end

  it 'ignores retained time fields when the schedule is disabled' do
    event = create(:event, :timed)

    expect(event.update(
      schedule_enabled: false,
      start_time: '6:00 PM',
      end_time: '9:00 PM',
      time_zone: 'Europe/Paris'
    )).to be(true)
    expect(event.reload).to have_attributes(starts_at: nil, ends_at: nil, time_zone: nil)
  end

  it 'rejects an incomplete schedule at the database boundary' do
    event = create(:event)

    expect do
      described_class.transaction(requires_new: true) do
        event.update_columns(starts_at: Time.current, time_zone: 'UTC')
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /events_schedule_complete/)
  end

  it 'rejects a non-increasing schedule at the database boundary' do
    event = create(:event)
    timestamp = Time.utc(event.date.year, event.date.month, event.date.day, 12)

    expect do
      described_class.transaction(requires_new: true) do
        event.update_columns(starts_at: timestamp, ends_at: timestamp, time_zone: 'UTC')
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /events_schedule_ordered/)
  end

  it 'rejects schedule timestamps outside the event date at the database boundary' do
    event = create(:event, date: Date.new(2026, 10, 10))

    expect do
      described_class.transaction(requires_new: true) do
        event.update_columns(
          starts_at: Time.utc(2026, 10, 11, 16),
          ends_at: Time.utc(2026, 10, 11, 17),
          time_zone: 'Europe/Paris'
        )
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /events_schedule_matches_date/)
  end

  it 'rejects an unknown schedule time zone at the database boundary' do
    event = create(:event)

    expect do
      described_class.transaction(requires_new: true) do
        event.update_columns(
          starts_at: Time.current,
          ends_at: 1.hour.from_now,
          time_zone: 'Atlantis/Nowhere'
        )
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /time zone .* not recognized/)
  end

  it 'stores descriptions in Action Text without a legacy events column' do
    expect(described_class.connection.column_exists?(:events, :body)).to be(false)
    expect(described_class.reflect_on_association(:rich_text_body)).to be_present
  end

  it 'publishes new events and shows guest names by default' do
    event = create(:event)
    expect(event.reload).to have_attributes(published: true, show_rsvp_names: true)
  end

  it 'rejects a missing publication state at the database boundary' do
    event = create(:event)

    expect do
      described_class.transaction(requires_new: true) { event.update_column(:published, nil) }
    end.to raise_error(ActiveRecord::NotNullViolation)
    expect(event.reload.published).to be(true)
  end

  it 'generates a different organizer credential for each saved event' do
    first, second = create_list(:event, 2)
    expect(first.admin_token).to match(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
    expect(first.admin_token).not_to eq(second.admin_token)
  end

  it 'keeps the organizer credential when editing an event' do
    event = create(:event)
    expect { event.update!(title: 'Updated party') }.not_to change { event.reload.admin_token }
  end

  it 'uses a readable slug with a decodable public hashid' do
    event = create(:event, title: "Alice's garden party!")
    expect(event.to_param).to eq("#{event.hashid}-alice-s-garden-party")
    expect(Event.find_by_hashid!(event.hashid)).to eq(event)
  end

  it 'changes only the title portion of the public URL after renaming' do
    event = create(:event)
    old_hashid = event.hashid
    event.update!(title: 'A new title')
    expect(event.to_param).to eq("#{old_hashid}-a-new-title")
  end

  it 'scopes responses to their event' do
    own = create(:rsvp)
    other = create(:rsvp)
    expect(own.event.rsvps).to contain_exactly(own)
    expect(own.event.rsvps).not_to include(other)
  end

  it 'deletes an event without responses' do
    event = create(:event)
    expect { event.destroy! }.to change(described_class, :count).by(-1)
  end

  it 'deletes an event and its responses together' do
    event = create(:rsvp).event
    expect { event.destroy! }.to change(Rsvp, :count).by(-1)
    expect(described_class.exists?(event.id)).to be(false)
  end
end
