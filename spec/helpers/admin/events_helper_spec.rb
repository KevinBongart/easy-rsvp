require 'rails_helper'

RSpec.describe Admin::EventsHelper, type: :helper do
  it 'uses one scale for actual and projected values and keeps dots inside the chart' do
    points = helper.sparkline_points([
      { label: '2025', count: 5 }, { label: '2026', count: 2, projected_count: 10 }
    ])
    expect(points.map { |point| [point[:x], point[:y]] }).to eq([[2, 10], [158, 2]])
  end

  it 'draws an empty history on a finite zero baseline' do
    points = helper.sparkline_points([{ label: '2025', count: 0 }, { label: '2026', count: 0, projected_count: 0 }])
    expect(helper.sparkline_coordinates(points)).to eq('2.0,18.0 158.0,18.0')
  end

  it 'formats large tooltip values and distinguishes estimates from actual counts' do
    expect(helper.sparkline_tooltip(label: '2026', count: 1234, projected_count: 3702)).to eq('2026: 1,234 so far; 3,702 extrapolated')
    expect(helper.sparkline_tooltip(label: 'September 30', projected_count: 3702)).to eq('September 30: 3,702 extrapolated')
  end
end
