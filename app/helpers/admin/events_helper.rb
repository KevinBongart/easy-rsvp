# frozen_string_literal: true

module Admin::EventsHelper
  def sparkline_points(series)
    maximum = [ series.map { |point| point[:projected_count] || point[:count] }.max, 1 ].max
    series.each_with_index.map do |point, index|
      # Leave space for the endpoint dots inside the 160 × 20 SVG.
      x = 2 + index * 156.0 / [ series.size - 1, 1 ].max
      value = point[:projected_count] || point[:count]
      y = 18 - value * 16.0 / maximum
      point.merge(x: x.round(2), y: y.round(2))
    end
  end

  def sparkline_coordinates(points)
    points.map { |point| "#{point[:x]},#{point[:y]}" }.join(" ")
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

  ROW_PATH_ID = "__event_id__"
  ROW_PATH_TOKEN = "__admin_token__"

  # Per-row URLs for the event list, built from templates generated once per
  # request. Route helpers plus Event#to_param (which slugifies the title) cost
  # about 0.1 ms per call, which adds up across 1,000 rows. The routes accept
  # the bare hashid, so these admin links skip the title slug.
  def admin_event_row_path(kind, event, hashid:)
    templates = @admin_event_row_path_templates ||= {
      public: event_path(ROW_PATH_ID),
      organizer: event_admin_path(ROW_PATH_ID, ROW_PATH_TOKEN),
      mark_spam: mark_spam_admin_event_path(ROW_PATH_ID),
      unmark_spam: unmark_spam_admin_event_path(ROW_PATH_ID)
    }
    path = templates.fetch(kind).sub(ROW_PATH_ID, hashid)
    kind == :organizer ? path.sub(ROW_PATH_TOKEN, event.admin_token) : path
  end
end
