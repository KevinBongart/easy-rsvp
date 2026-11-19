require 'rails_helper'

RSpec.describe Admin::DailyCreationCounts do
  let(:now) { Time.utc(2026, 11, 19, 12) }

  it 'counts spam and legitimate events per UTC day over 90 days, zero-filling quiet days' do
    travel_to now do
      create(:event, created_at: Time.utc(2026, 8, 21, 23, 59, 59)) # the day before the window
      create(:event, :spam, created_at: Time.utc(2026, 8, 22, 0, 0, 0)) # first day of the window
      create(:event, created_at: Time.utc(2026, 10, 1, 9))
      create(:event, :flagged_as_spam).update_columns(created_at: Time.utc(2026, 10, 1, 23, 59))
      create(:event, :spam, created_at: Time.utc(2026, 10, 1, 10))
      create(:event, created_at: Time.utc(2026, 11, 19, 23, 30)) # later today
      create(:event, created_at: Time.utc(2026, 11, 20, 0, 0)) # tomorrow in UTC

      counts = described_class.new(Event.all, now: now)
      series = counts.series

      expect(series.size).to eq(90)
      expect(series.first).to eq(date: Date.new(2026, 8, 22), spam: 1, legitimate: 0)
      expect(series.last).to eq(date: Date.new(2026, 11, 19), spam: 0, legitimate: 1)
      expect(series.find { |day| day[:date] == Date.new(2026, 10, 1) }).to eq(date: Date.new(2026, 10, 1), spam: 2, legitimate: 1)
      expect(series.find { |day| day[:date] == Date.new(2026, 10, 2) }).to eq(date: Date.new(2026, 10, 2), spam: 0, legitimate: 0)
      expect(series.map { |day| day[:date] }).to eq((Date.new(2026, 8, 22)..Date.new(2026, 11, 19)).to_a)
      expect([ counts.spam_total, counts.legitimate_total, counts.maximum ]).to eq([ 3, 2, 2 ])
    end
  end

  it 'uses the UTC day even when the application time zone differs' do
    Time.use_zone('Pacific/Auckland') do
      create(:event, created_at: Time.utc(2026, 11, 18, 20)) # November 19 in Auckland

      series = described_class.new(Event.all, now: Time.utc(2026, 11, 19, 12).in_time_zone).series

      expect(series.last(2).map { |day| day[:legitimate] }).to eq([ 1, 0 ])
    end
  end

  it 'aggregates in a single query' do
    create(:event, :spam)
    create(:event)
    counts = described_class.new(Event.all)

    expect(count_queries { counts.series }).to eq(1)
    expect(count_queries { [ counts.spam_total, counts.legitimate_total, counts.maximum ] }).to eq(0)
  end

  it 'renders an empty window as zeros' do
    counts = described_class.new(Event.all, now: now, days: 3)
    expect(counts.series.map { |day| [ day[:spam], day[:legitimate] ] }).to eq([ [ 0, 0 ] ] * 3)
    expect(counts.maximum).to eq(0)
  end
end
