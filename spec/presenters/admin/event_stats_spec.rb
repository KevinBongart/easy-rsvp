require 'rails_helper'

RSpec.describe Admin::EventStats do
  let(:now) { Time.zone.local(2026, 9, 10, 12) }

  def entry(date:, created_at: date)
    Event.new(date: date, created_at: created_at)
  end

  it 'renders empty statistics without division errors' do
    stats = described_class.new([], now: now)
    expect(stats.total_events).to eq('0')
    expect(stats.yearly_counts).to eq({})
    expect(stats.current_month_count).to eq('0')
    expect(stats.extrapolated_current_month_count).to eq('0')
  end

  it 'formats totals with thousands separators' do
    expect(described_class.new(Array.new(1234), now: now).total_events).to eq('1,234')
  end

  it 'groups creation years newest first' do
    rows = [entry(date: Date.new(2024, 1, 1)), entry(date: Date.new(2026, 1, 1)), entry(date: Date.new(2026, 2, 1))]
    stats = described_class.new(rows, now: now)
    expect(stats.yearly_counts.to_a).to eq([[2026, '2'], [2024, '1']])
    expect(stats.yearly_counts_display).to eq('2026: 2, 2024: 1')
  end

  it 'includes the first day and excludes the next month from a monthly bucket' do
    rows = [entry(date: Date.new(2026, 9, 1)), entry(date: Date.new(2026, 9, 30)), entry(date: Date.new(2026, 10, 1))]
    expect(described_class.new(rows, now: now).current_month_count).to eq('2')
  end

  it 'fills missing months with zero and honors the requested history length' do
    stats = described_class.new([], now: now, months_back: 2)
    expect(stats.monthly_counts_with_labels).to eq([['September 2026', '0'], ['August 2026', '0'], ['July 2026', '0']])
    expect(stats.full_months_display).to eq('August 2026: 0, July 2026: 0')
  end

  it 'labels history correctly across a year boundary' do
    stats = described_class.new([], now: Time.zone.local(2026, 1, 10), months_back: 2)
    expect(stats.full_months_display).to eq('December 2025: 0, November 2025: 0')
  end

  it 'extrapolates a monthly count using elapsed days' do
    rows = Array.new(5) { entry(date: Date.new(2026, 9, 2)) }
    stats = described_class.new(rows, now: now)
    expect(stats.current_month_label).to eq('September 2026')
    expect(stats.extrapolated_current_month_count).to eq('15')
  end

  it 'handles leap-year February at the last day without inflating the total' do
    stats = described_class.new([entry(date: Date.new(2024, 2, 29))], now: Time.zone.local(2024, 2, 29))
    expect(stats.extrapolated_current_month_count).to eq('1')
  end

  it 'performs no SQL when given already loaded events' do
    rows = build_list(:event, 3, created_at: now)
    stats = described_class.new(rows, now: now)
    expect(count_queries { stats.total_events; stats.full_months_display; stats.yearly_counts }).to eq(0)
  end
end
