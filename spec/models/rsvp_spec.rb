require 'rails_helper'

RSpec.describe Rsvp, type: :model do
  it 'builds a valid response without seed data' do
    expect(build(:rsvp)).to be_valid
  end

  [ :name, :response, :event ].each do |attribute|
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

  it 'requires an event at the database boundary' do
    rsvp = create(:rsvp)

    expect do
      described_class.transaction(requires_new: true) { rsvp.update_column(:event_id, nil) }
    end.to raise_error(ActiveRecord::NotNullViolation)
    expect(rsvp.reload.event).to be_present
  end

  [ nil, '', '   ', "\t\n" ].each do |name|
    it "rejects the guest name #{name.inspect} at the database boundary" do
      rsvp = create(:rsvp)

      expected_error = name.nil? ? ActiveRecord::NotNullViolation : ActiveRecord::StatementInvalid
      expect do
        described_class.transaction(requires_new: true) { rsvp.update_column(:name, name) }
      end.to raise_error(expected_error)
      expect(rsvp.reload.name).to be_present
    end
  end

  [ nil, 'unexpected' ].each do |answer|
    it "rejects #{answer.inspect} even when model validation is bypassed" do
      rsvp = create(:rsvp)
      expect do
        described_class.transaction(requires_new: true) { rsvp.update_column(:response, answer) }
      end.to raise_error(ActiveRecord::StatementInvalid) { |error| expect(error.cause).to be_a(PG::CheckViolation) }
      expect(rsvp.reload.response).to eq('yes')
    end
  end

  it 'has a validated database constraint for supported responses' do
    constraint = ActiveRecord::Base.connection.check_constraints(:rsvps)
      .find { |candidate| candidate.name == 'rsvps_supported_response' }

    expect(constraint).to be_present
    expect(constraint.options[:validate]).to be(true)
  end

  it 'has a validated database constraint for nonblank guest names' do
    constraint = ActiveRecord::Base.connection.check_constraints(:rsvps)
      .find { |candidate| candidate.name == 'rsvps_name_present' }

    expect(constraint).to be_present
    expect(constraint.options[:validate]).to be(true)
  end

  describe 'name length' do
    let(:limit) { described_class::MAXIMUM_NAME_LENGTH }

    it 'accepts names up to the limit and refuses longer ones' do
      expect(build(:rsvp, name: 'a' * limit)).to be_valid

      rsvp = build(:rsvp, name: 'a' * (limit + 1))
      expect(rsvp).not_to be_valid
      expect(rsvp.errors.full_messages).to eq([ "Name is too long (maximum is #{limit} characters)" ])
    end

    it 'keeps older long names editable as long as they do not grow' do
      rsvp = create(:rsvp)
      rsvp.update_column(:name, 'a' * (limit + 50))

      expect(rsvp.update(name: 'a' * (limit + 10))).to be(true)
      expect(rsvp.update(response: 'no')).to be(true)
      expect(rsvp.update(name: 'a' * (limit + 11))).to be(false)
    end
  end

  describe 'names that are not names' do
    [
      'Check https://example.test/deal', 'www.cheap-deals.example', 'cheap-pills.shop', 'visit BESTDEALS.com today',
      'shop.example.com', 'Win big at go.casino.xyz', 'Ivan (shop.ru)',
      "\uFF43\uFF41\uFF53\uFF49\uFF4E\uFF4F\uFF0E\uFF43\uFF4F\uFF4D", "casino.c\u200Bom", "\uFF50\uFF52\uFF4F\uFF4D\uFF4F \uFF43\uFF4F\uFF44\uFF45 SAVE20",
      "a#{"\u0301" * 16}",
      'Use promo code SAVE20', 'Best online casino bonus', 'Free robux generator', 'Flight booking 1-800-555-0199'
    ].each do |name|
      it "refuses #{name.inspect} without saying why" do
        rsvp = build(:rsvp, name:)
        expect(rsvp).not_to be_valid
        expect(rsvp.errors.full_messages).to eq([ 'Name should be just your name' ])
      end
    end

    [
      'Alex', 'Mary-Jane O’Brien', 'Dr. Who + 2 kids', 'J.R.R. Tolkien', 'Ann & Bob (bringing salad)',
      'alex@example.com', 'a@mail.example.com', 'anna@mail.ru', 'Sam from acme.de', 'Casino night crew', 'Customer service team', '_dj_mike_', '𝓙𝓸𝓱𝓷',
      '山田太郎', 'Иван Петров', 'محمد علي', 'יוסי כהן', 'नेहा शर्मा', 'Nguyễn Văn An', '김민준 +1', 'Ζωή Παπαδοπούλου', 'สมชาย ใจดี',
      "Mehdi \u0645\u06CC\u200C\u062E\u0648\u0627\u0647\u0645", "Family \u{1F468}\u200D\u{1F469}\u200D\u{1F467}", "Z#{"\u0301" * 15}"
    ].each do |name|
      it "accepts #{name.inspect}" do
        expect(build(:rsvp, name:)).to be_valid
      end
    end

    it 'saves names as typed, keeping the zero-width joiners some scripts need' do
      name = "Mehdi \u0645\u06CC\u200C\u062E\u0648\u0627\u0647\u0645"
      expect(create(:rsvp, name:).reload.name).to eq(name)
    end

    [ "\u200B", "\u3164", " \u200B\u2060 " ].each do |name|
      it "treats the invisible name #{name.inspect} as blank" do
        rsvp = build(:rsvp, name:)
        expect(rsvp).not_to be_valid
        expect(rsvp.errors.of_kind?(:name, :blank)).to be(true)
      end
    end

    it 'only checks names when they change' do
      rsvp = create(:rsvp)
      rsvp.update_column(:name, 'www.old-name.example')

      expect(rsvp.update(response: 'no')).to be(true)
    end
  end
end
