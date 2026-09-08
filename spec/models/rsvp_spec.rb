require 'rails_helper'

RSpec.describe Rsvp, type: :model do
  it 'builds a valid response without seed data' do
    expect(build(:rsvp)).to be_valid
  end

  [:name, :response, :event].each do |attribute|
    it "requires #{attribute}" do
      rsvp = build(:rsvp, attribute => nil)
      expect(rsvp).not_to be_valid
      expect(rsvp.errors[attribute]).to be_present
    end
  end

  %w[yes maybe no].each do |answer|
    it "persists a #{answer} answer" do
      rsvp = create(:rsvp, response: answer)
      expect(rsvp.reload.response).to eq(answer)
    end
  end

  it 'rejects answers outside the supported choices' do
    expect(build(:rsvp, response: 'unexpected')).not_to be_valid
  end

  it 'does not impose account-style uniqueness on guest names' do
    first = create(:rsvp, name: 'Alex')
    expect(create(:rsvp, event: first.event, name: 'Alex')).to be_persisted
  end

  it 'looks up responses through their public hashids' do
    rsvp = create(:rsvp)
    expect(described_class.find(rsvp.to_param)).to eq(rsvp)
  end

  it 'excludes built unsaved responses from the persisted association scope' do
    rsvp = create(:rsvp)
    rsvp.event.rsvps.build(name: 'Not submitted', response: 'maybe')
    expect(rsvp.event.rsvps.persisted).to contain_exactly(rsvp)
  end

  it 'enforces the event foreign key even when model validations are bypassed' do
    rsvp = create(:rsvp)
    missing_id = Event.maximum(:id) + 1
    expect do
      described_class.transaction(requires_new: true) { rsvp.update_column(:event_id, missing_id) }
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(rsvp.reload.event).to be_present
  end

  [nil, 'unexpected'].each do |answer|
    it "rejects #{answer.inspect} even when model validation is bypassed" do
      rsvp = create(:rsvp)
      expect do
        described_class.transaction(requires_new: true) { rsvp.update_column(:response, answer) }
      end.to raise_error(ActiveRecord::StatementInvalid) { |error| expect(error.cause).to be_a(PG::CheckViolation) }
      expect(rsvp.reload.response).to eq('yes')
    end
  end

end
