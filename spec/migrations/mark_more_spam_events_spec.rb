require 'rails_helper'
require Rails.root.join('db/migrate/20261118130000_mark_more_spam_events')

RSpec.describe MarkMoreSpamEvents do
  let(:wave) { Time.zone.local(2026, 11, 18, 11, 34) }

  def run_migration
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  def event_at(time, id: nil, rsvps: 0, **attributes)
    create(:event, id: id, created_at: time, **attributes).tap do |event|
      create_list(:rsvp, rsvps, event: event)
    end
  end

  it 'marks reviewed events created during the wave, even with RSVPs' do
    followers = event_at(wave, id: 17382, rsvps: 46, title: 'Free Instagram Followers: The 2026 Expert Evaluation')

    run_migration

    expect(followers.reload).to be_spam
  end

  it 'leaves reviewed IDs alone when they belong to events created before the wave' do
    older = event_at(Time.zone.local(2026, 11, 1), id: 12520, title: 'Book club')

    run_migration

    expect(older.reload).not_to be_spam
  end

  it 'marks spam titles on the topics the first pass missed' do
    titles = [
      'Earn Robux Free Easily: Updated Methods That Actually Work',
      'Pokemon GO Spoofer iOS & Android 2026',
      'Get Google Play Redeem Code Free (November 2026)',
      'BitStarz 30 Free Spins No Deposit 2026',
      'Best Bitcoin Casinos: Crypto Gambling Sites Ranked',
      '𝓢𝓱𝓮𝓲𝓷 New Shoppers'
    ]
    events = titles.map { |title| event_at(wave, title: title) }

    run_migration

    expect(events.map { |event| event.reload.spam? }).to all(be(true))
  end

  it 'still applies the original classifier to events created after the first pass' do
    iptv = event_at(wave, title: '7 Best IPTV Service 2026: Top 7 Providers Compared')

    run_migration

    expect(iptv.reload).to be_spam
  end

  it 'keeps ordinary events and does not touch earlier marks' do
    dinner = event_at(wave, rsvps: 3, title: 'Gokay and Greg Osaka Dinner')
    earlier_mark = Time.zone.local(2026, 11, 18, 11, 32)
    marked = event_at(wave, title: 'Peptides coupon code', spam_at: earlier_mark)

    run_migration

    expect(dinner.reload).not_to be_spam
    expect(marked.reload.spam_at).to eq(earlier_mark)
  end
end
