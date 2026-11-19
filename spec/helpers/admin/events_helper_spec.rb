require 'rails_helper'

RSpec.describe Admin::EventsHelper, type: :helper do
  it 'uses one scale for actual and projected values and keeps dots inside the chart' do
    points = helper.sparkline_points([
      { label: '2025', count: 5 }, { label: '2026', count: 2, projected_count: 10 }
    ])
    expect(points.map { |point| [ point[:x], point[:y] ] }).to eq([ [ 2, 10 ], [ 158, 2 ] ])
  end

  it 'draws an empty history on a finite zero baseline' do
    points = helper.sparkline_points([ { label: '2025', count: 0 }, { label: '2026', count: 0, projected_count: 0 } ])
    expect(helper.sparkline_coordinates(points)).to eq('2.0,18.0 158.0,18.0')
  end

  it 'scales both daily series to one maximum across the full chart width' do
    days = [
      { date: Date.new(2026, 11, 17), spam: 4, legitimate: 0 },
      { date: Date.new(2026, 11, 18), spam: 0, legitimate: 2 },
      { date: Date.new(2026, 11, 19), spam: 1_234, legitimate: 0 }
    ]
    points = helper.daily_chart_points(days.first(2), maximum: 4)
    expect(helper.daily_chart_coordinates(points, :spam)).to eq('0.0,2.0 160.0,118.0')
    expect(helper.daily_chart_coordinates(points, :legitimate)).to eq('0.0,118.0 160.0,60.0')
    expect(helper.daily_chart_coordinates(helper.daily_chart_points([ days.first.merge(spam: 0) ], maximum: 0), :spam)).to eq('0.0,118.0')

    points = helper.daily_chart_points(days, maximum: 1_234)
    expect(helper.daily_chart_tooltip(points.last)).to eq('November 19, 2026: 1,234 spam, 0 legitimate')
    expect(helper.daily_chart_tooltip_position(points, 0)).to eq('left: 0.0%')
    expect(helper.daily_chart_tooltip_position(points, 2)).to eq('right: 0.0%')
  end

  it 'formats large tooltip values and distinguishes estimates from actual counts' do
    expect(helper.sparkline_tooltip(label: '2026', count: 1234, projected_count: 3702)).to eq('2026: 1,234 so far; 3,702 extrapolated')
    expect(helper.sparkline_tooltip(label: 'September 30', projected_count: 3702)).to eq('September 30: 3,702 extrapolated')
  end
end
