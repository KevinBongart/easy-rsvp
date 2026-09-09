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
    expect(stats.oldest_creation_date).to be_nil
    expect(stats.current_year_count).to eq('0')
    expect(stats.extrapolated_current_year_count).to eq('0')
  end

  it 'labels the first creation date regardless of event order or scheduled dates' do
    rows = [entry(date: Date.new(2010, 1, 1), created_at: Time.zone.local(2025, 9, 8)),
            entry(date: Date.new(2030, 1, 1), created_at: Time.zone.local(2018, 2, 3))]
    expect(described_class.new(rows, now: now).oldest_creation_date).to eq('February 3, 2018')
  end

  it 'formats the current year count and projection from the same data as its chart' do
    rows = Array.new(1234) { entry(date: Date.new(2030, 1, 1), created_at: now) }
    rows << entry(date: Date.new(2030, 1, 1), created_at: Time.zone.local(2025, 1, 1))
    stats = described_class.new(rows, now: now)
    expect(stats.current_year_count).to eq('1,234')
    expect(stats.extrapolated_current_year_count).to eq('1,780')
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

  context 'creation-date statistics' do
    it 'assigns an event to its creation year when the party is in another year' do
      rows = [entry(date: Date.new(2027, 1, 5), created_at: Time.zone.local(2026, 12, 20))]
      stats = described_class.new(rows, now: Time.zone.local(2027, 1, 10))
      expect(stats.yearly_counts).to eq(2026 => '1')
    end

    it 'counts events created this month regardless of their scheduled month' do
      rows = [
        entry(date: Date.new(2026, 11, 5), created_at: Time.zone.local(2026, 9, 2)),
        entry(date: Date.new(2026, 12, 5), created_at: Time.zone.local(2026, 9, 3)),
        entry(date: Date.new(2026, 9, 5), created_at: Time.zone.local(2026, 8, 20))
      ]
      expect(described_class.new(rows, now: now).current_month_count).to eq('2')
    end

    it 'puts a December creation in December history even when the party is in January' do
      rows = [entry(date: Date.new(2027, 1, 5), created_at: Time.zone.local(2026, 12, 20))]
      stats = described_class.new(rows, now: Time.zone.local(2027, 1, 10), months_back: 1)
      expect(stats.monthly_counts_with_labels).to eq([['January 2027', '0'], ['December 2026', '1']])
    end

    it 'uses creation timestamps at the exact start and end of a month' do
      rows = [
        entry(date: Date.new(2026, 11, 5), created_at: Time.zone.local(2026, 9, 1)),
        entry(date: Date.new(2026, 11, 5), created_at: Time.zone.local(2026, 9, 30, 23, 59, 59)),
        entry(date: Date.new(2026, 11, 5), created_at: Time.zone.local(2026, 10, 1))
      ]
      stats = described_class.new(rows, now: Time.zone.local(2026, 9, 30, 23, 59, 59))
      expect(stats.current_month_count).to eq('2')
    end

    it 'keeps growth history unchanged when an organizer reschedules a party' do
      event = entry(date: Date.new(2026, 9, 5), created_at: Time.zone.local(2026, 9, 2))
      original = described_class.new([event], now: now).monthly_counts_with_labels
      event.date = Date.new(2026, 11, 5)
      expect(described_class.new([event], now: now).monthly_counts_with_labels).to eq(original)
    end

    it 'projects this months creation rate without using scheduled party dates' do
      rows = Array.new(5) do
        entry(date: Date.new(2026, 11, 5), created_at: Time.zone.local(2026, 9, 2))
      end
      rows << entry(date: Date.new(2026, 9, 25), created_at: Time.zone.local(2026, 8, 20))
      expect(described_class.new(rows, now: now).extrapolated_current_month_count).to eq('15')
    end
  end

  describe 'chart series' do
    it 'orders years chronologically, fills gaps, and projects only the current year' do
      rows = [entry(date: Date.new(2030, 1, 1), created_at: Time.zone.local(2024, 2, 1)),
              entry(date: Date.new(2030, 1, 1), created_at: Time.zone.local(2026, 2, 1))]
      stats = described_class.new(rows, now: Time.zone.local(2026, 7, 1))
      expect(stats.yearly_chart).to eq([
        { label: '2024', count: 1 }, { label: '2025', count: 0 },
        { label: '2026 through July 1', count: 1 },
        { label: '2026 through December 31', projected_count: 2 }
      ])
    end

    it 'adds the current month projection after the completed monthly history' do
      rows = Array.new(5) { entry(date: Date.new(2030, 1, 1), created_at: Time.zone.local(2026, 9, 2)) }
      stats = described_class.new(rows, now: now, months_back: 2)
      expect(stats.monthly_chart).to eq([
        { label: 'July 2026', count: 0 }, { label: 'August 2026', count: 0 },
        { label: 'September 2026', count: 5, projected_count: 15 }
      ])
    end

    it 'keeps large projections numeric and shares the displayed monthly estimate' do
      stats = described_class.new(Array.new(1234) { entry(date: Date.new(2026, 9, 2)) }, now: now)
      expect(stats.monthly_chart.last[:projected_count]).to eq(3702)
      expect(stats.extrapolated_current_month_count).to eq('3,702')
    end

    it 'renders a zero baseline and forecast for an empty database' do
      stats = described_class.new([], now: now)
      expect(stats.yearly_chart).to eq([
        { label: '2025', count: 0 }, { label: '2026 through September 10', count: 0 },
        { label: '2026 through December 31', projected_count: 0 }
      ])
      expect(stats.monthly_chart.size).to eq(13)
      expect(stats.monthly_chart.first[:label]).to eq('September 2025')
      expect(stats.monthly_chart.last[:projected_count]).to eq(0)
    end

    it 'uses all 366 days when projecting a leap year' do
      stats = described_class.new([entry(date: Date.new(2024, 1, 1))], now: Time.zone.local(2024, 1, 1))
      expect(stats.yearly_chart.last[:projected_count]).to eq(366)
    end

    it 'shows cumulative daily creations through today, then a month-end forecast' do
      rows = [entry(date: Date.new(2030, 1, 1), created_at: Time.zone.local(2026, 9, 1)),
              entry(date: Date.new(2030, 1, 1), created_at: Time.zone.local(2026, 9, 3)),
              entry(date: Date.new(2030, 1, 1), created_at: Time.zone.local(2026, 8, 31))]
      stats = described_class.new(rows, now: Time.zone.local(2026, 9, 4))
      expect(stats.current_month_chart.first(4)).to eq([
        { label: 'September 1', count: 1 }, { label: 'September 2', count: 1 },
        { label: 'September 3', count: 2 }, { label: 'September 4', count: 2 }
      ])
      expect(stats.current_month_chart[4]).to eq(label: 'September 5', projected_count: 3)
      expect(stats.current_month_chart.last).to eq(label: 'September 30', projected_count: 15)
      expect(stats.current_month_chart.size).to eq(30)
    end

    it 'has no future forecast on the last day of a leap-year February' do
      stats = described_class.new([entry(date: Date.new(2024, 2, 29))], now: Time.zone.local(2024, 2, 29))
      expect(stats.current_month_chart.size).to eq(29)
      expect(stats.current_month_chart.last).to eq(label: 'February 29', count: 1)
      expect(stats.current_month_chart).to all(satisfy { |point| !point.key?(:projected_count) })
    end

    it 'handles the first day of a month and keeps all charts query-free' do
      stats = described_class.new([], now: Time.zone.local(2026, 1, 1))
      expect(count_queries { stats.yearly_chart; stats.monthly_chart; stats.current_month_chart }).to eq(0)
      expect(stats.current_month_chart.first).to eq(label: 'January 1', count: 0)
      expect(stats.current_month_chart.last).to eq(label: 'January 31', projected_count: 0)
    end
  end

end
