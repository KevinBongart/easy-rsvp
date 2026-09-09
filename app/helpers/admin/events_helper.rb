# frozen_string_literal: true

module Admin::EventsHelper
  def sparkline_points(series)
    maximum = [series.map { |point| point[:projected_count] || point[:count] }.max, 1].max
    series.each_with_index.map do |point, index|
      # Leave space for the endpoint dots inside the 160 × 20 SVG.
      x = 2 + index * 156.0 / [series.size - 1, 1].max
      value = point[:projected_count] || point[:count]
      y = 18 - value * 16.0 / maximum
      point.merge(x: x.round(2), y: y.round(2))
    end
  end

  def sparkline_coordinates(points)
    points.map { |point| "#{point[:x]},#{point[:y]}" }.join(' ')
  end

  def sparkline_tooltip(point)
    label = "#{point[:label]}: "
    if point.key?(:projected_count)
      label += "#{number_with_delimiter(point[:count])} so far; " if point.key?(:count)
      label + "#{number_with_delimiter(point[:projected_count])} extrapolated"
    else
      label + number_with_delimiter(point[:count])
    end
  end

  def sparkline_hit_area(points, index)
    left = index.zero? ? 0 : (points[index - 1][:x] + points[index][:x]) / 2.0
    right = index == points.size - 1 ? 160 : (points[index][:x] + points[index + 1][:x]) / 2.0
    "left: #{left / 1.6}%; width: #{(right - left) / 1.6}%"
  end
end
