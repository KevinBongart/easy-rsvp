require 'rails_helper'
require Rails.root.join('db/migrate/20261118120000_add_spam_at_to_events')

RSpec.describe AddSpamAtToEvents do
  let(:wave) { Time.zone.local(2026, 11, 17, 9, 0) }

  # This migration predates events.spam_source, its consistency check, and
  # automatic flagging on save.
  before do
    ActiveRecord::Base.connection.remove_check_constraint :events, name: 'events_spam_source_matches_spam_at'
    # Sample events must reach the migration unmarked.
    allow(Event::SpamCheck).to receive(:spam?).and_return(false)
  end

  def mark_spam
    sql = ActiveRecord::Base.sanitize_sql([ described_class::MARK_SPAM_SQL, { since: described_class::SPAM_WAVE_STARTED_ON } ])
    ActiveRecord::Base.connection.exec_update(sql)
  end

  def event_at(time, rsvps: 0, **attributes)
    create(:event, created_at: time, **attributes).tap do |event|
      create_list(:rsvp, rsvps, event: event)
    end
  end

  it 'marks spam titles, long link-heavy bodies, and long bodies nobody answered' do
    coupon = event_at(wave, title: 'NextGen Peptides working coupon code: NEX55')
    bracketed = event_at(wave, title: 'Julius AI 〖KANNY〗 – Flat 25% Off')
    phone = event_at(wave, title: 'Airline support 1-888-555-0199 call now')
    linky = event_at(wave, title: 'Best guide', body: "<div>#{'word ' * 900}<a href=\"https://a.example\">a</a><a href=\"https://b.example\">b</a></div>")
    long = event_at(wave, title: 'Ultimate guide', body: "<div>#{'word ' * 1300}</div>")

    expect(mark_spam).to eq(5)
    expect([ coupon, bracketed, phone, linky, long ].map { |event| event.reload.spam? }).to all(be(true))
  end

  it 'keeps legitimate events that match a keyword but have guests' do
    party = event_at(wave, rsvps: 16, title: 'Cozy House Casino birthday')

    mark_spam

    expect(party.reload).not_to be_spam
  end

  it 'keeps ordinary new events' do
    dinner = event_at(wave, title: 'Friday dinner', body: '<div>See you at <a href="https://maps.example">the place</a></div>')
    promotion = event_at(wave, title: 'Promotion party for Sam')

    mark_spam

    expect([ dinner, promotion ].map { |event| event.reload.spam? }).to all(be(false))
  end

  it 'ignores events created before the spam wave' do
    old = event_at(Time.zone.local(2026, 11, 15, 23, 0), title: 'Hostinger coupon code')

    mark_spam

    expect(old.reload).not_to be_spam
  end
end
