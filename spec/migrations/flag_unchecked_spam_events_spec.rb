require 'rails_helper'
require Rails.root.join('db/migrate/20261118150000_flag_unchecked_spam_events')

RSpec.describe FlagUncheckedSpamEvents do
  let(:wave) { Time.zone.local(2026, 11, 18, 12, 0) }

  def run_migration
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  # Events created before the save-time check existed reached the database
  # unchecked; recreate that state.
  def unchecked_event(created_at: wave, **attributes)
    create(:event, created_at: created_at, **attributes).tap do |event|
      event.update_columns(spam_at: nil, spam_source: nil)
    end
  end

  it 'flags unchecked spam created since the wave as automatic' do
    spam = unchecked_event(title: 'Earn Robux Free Easily')

    run_migration

    expect(spam.reload).to have_attributes(spam_source: 'automatic', spam_at: be_present)
  end

  it 'checks the description too' do
    spam = unchecked_event(title: 'Guide', body: '<h2>Why</h2><p>Buy now</p>')

    run_migration

    expect(spam.reload).to be_flagged_as_spam
  end

  it 'leaves real events, older events, and existing marks alone' do
    real = unchecked_event(title: 'Garden party')
    older = unchecked_event(title: 'Earn Robux Free Easily', created_at: Time.zone.local(2026, 11, 1))
    operator = create(:event, :spam, title: 'Robux generator', created_at: wave)

    run_migration

    expect(real.reload).not_to be_spam
    expect(older.reload).not_to be_spam
    expect(operator.reload.spam_source).to eq('operator')
  end
end
