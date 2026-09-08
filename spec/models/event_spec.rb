require 'rails_helper'

RSpec.describe Event, type: :model do
  it 'builds a valid event without seed data' do
    expect(build(:event)).to be_valid
  end

  [:title, :date].each do |attribute|
    it "requires #{attribute}" do
      event = build(:event, attribute => nil)
      expect(event).not_to be_valid
      expect(event.errors[attribute]).to be_present
    end
  end

  it 'allows an empty description' do
    expect(build(:event, body: nil)).to be_valid
  end

  it 'publishes new events and shows guest names by default' do
    event = create(:event)
    expect(event.reload).to have_attributes(published: true, show_rsvp_names: true)
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
    pending 'Assessment 1.1: Event has no dependent RSVP deletion policy'
    event = create(:rsvp).event
    expect { event.destroy! }.to change(Rsvp, :count).by(-1)
    expect(described_class.exists?(event.id)).to be(false)
  end
end
