class Event < ApplicationRecord
  include Hashid::Rails

  TIME_PATTERN = /\A(?<hour>\d{1,2}):(?<minute>\d{2})\z/

  has_many :rsvps, dependent: :destroy
  has_rich_text :body

  attr_writer :start_time, :end_time

  normalizes :time_zone, with: ->(time_zone) { time_zone.presence }

  before_validation :apply_submitted_schedule, if: :schedule_submitted?
  before_create :set_admin_token

  validates :title, presence: true
  validates :date, presence: true
  validates :published, inclusion: { in: [ true, false ] }
  validate :schedule_columns_are_complete, unless: :schedule_submitted?
  validate :time_zone_is_known
  validate :schedule_ends_after_it_starts
  validate :schedule_uses_event_date

  def timed
    schedule_submitted? ? @timed : starts_at.present?
  end

  def timed=(value)
    @timed = ActiveModel::Type::Boolean.new.cast(value)
  end

  def timed?
    timed
  end

  def start_time
    return @start_time if instance_variable_defined?(:@start_time)

    local_schedule_time(starts_at)
  end

  def end_time
    return @end_time if instance_variable_defined?(:@end_time)

    local_schedule_time(ends_at)
  end

  def to_param
    "#{hashid}-#{title.parameterize}"
  end

  private

  def schedule_submitted?
    instance_variable_defined?(:@timed)
  end

  def apply_submitted_schedule
    unless timed?
      self.starts_at = nil
      self.ends_at = nil
      self.time_zone = nil
      return
    end

    self.time_zone = time_zone.presence
    zone = schedule_zone

    if time_zone.blank?
      errors.add(:time_zone, "can't be blank")
    elsif !zone
      errors.add(:time_zone, "isn't recognized")
    end
    errors.add(:start_time, "can't be blank") if start_time.blank?
    errors.add(:end_time, "can't be blank") if end_time.blank?
    return unless date && zone

    self.starts_at = schedule_time(start_time, zone, :start_time)
    self.ends_at = schedule_time(end_time, zone, :end_time)
  end

  def schedule_time(value, zone, attribute)
    match = TIME_PATTERN.match(value.to_s)
    hour = match && Integer(match[:hour], 10, exception: false)
    minute = match && Integer(match[:minute], 10, exception: false)

    unless hour&.between?(0, 23) && minute&.between?(0, 59)
      errors.add(attribute, "isn't a valid time") if value.present?
      return
    end

    local_time = zone.local(date.year, date.month, date.day, hour, minute)
    if local_time.hour != hour || local_time.min != minute
      errors.add(attribute, "doesn't exist in this time zone")
      return
    end

    local_time
  end

  def schedule_columns_are_complete
    schedule_values = [ starts_at, ends_at, time_zone.presence ]
    return if schedule_values.all?(&:nil?) || schedule_values.none?(&:nil?)

    errors.add(:base, "A timed event needs a start time, end time, and time zone")
  end

  def time_zone_is_known
    return if time_zone.blank? || schedule_zone

    errors.add(:time_zone, "isn't recognized") unless errors.added?(:time_zone, "isn't recognized")
  end

  def schedule_ends_after_it_starts
    return unless starts_at && ends_at && ends_at <= starts_at

    attribute = schedule_submitted? ? :end_time : :ends_at
    errors.add(attribute, "must be after the start time")
  end

  def schedule_uses_event_date
    return unless date && starts_at && ends_at && (zone = schedule_zone)
    return if starts_at.in_time_zone(zone).to_date == date && ends_at.in_time_zone(zone).to_date == date

    errors.add(:base, "Event times must be on the event date")
  end

  def local_schedule_time(value)
    return unless value && (zone = schedule_zone)

    value.in_time_zone(zone).to_fs(:time_input)
  end

  def schedule_zone
    return if time_zone.blank?

    ActiveSupport::TimeZone[TZInfo::Timezone.get(time_zone)]
  rescue TZInfo::InvalidTimezoneIdentifier
    nil
  end

  def set_admin_token
    self.admin_token = SecureRandom.uuid
  end
end
