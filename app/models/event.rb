class Event < ApplicationRecord
  include Hashid::Rails

  TIME_PATTERN = /\A(?<hour>\d{1,2})(?::(?<minute>\d{1,2}))?\s*(?<meridiem>[ap](?:\.?m\.?)?)?\z/i

  # Limits checked only when the field changes, and never against an edit that
  # does not make an older, larger event worse, so those stay editable.
  # Legitimate data (2026-11 snapshot): titles p99 73 characters; 13 of 4,889
  # descriptions over 3,000 characters; embedded images up to 7.9 MB each.
  MAXIMUM_TITLE_LENGTH = 200
  MAXIMUM_DESCRIPTION_LENGTH = 20_000
  MAXIMUM_IMAGES_SIZE = 10.megabytes
  # Captures the signed blob id of an Active Storage URL, on current
  # (redirect/proxy) and legacy routes.
  LEGACY_UPLOAD_URL = %r{/rails/active_storage/(?:blobs|representations)/(?:redirect/|proxy/)?([^/?#]+)}
  IMAGES_TOO_LARGE ="Images in the description can add up to 10 MB; remove some and try again.".freeze

  # An automatic flag this certain is never revealed to the organizer: the
  # rules are public, so telling spammers they were caught teaches them what
  # to edit away. On the 2026-11-20 production copy, no legitimate event ever
  # met either bar, while 6,149 of 6,277 spam events (34 of the 38 since
  # November 19) did.
  CONFIDENT_SPAM_REASONS = 2
  CONFIDENT_SPAM_SCORE = 0.98
  # How long images of spam stay stored after the mark or flag (see
  # Event::SpamImages).
  SPAM_IMAGE_RETENTION = 30.days

  has_many :rsvps, dependent: :destroy
  has_rich_text :body

  scope :spam, -> { where.not(spam_at: nil) }
  scope :not_spam, -> { where(spam_at: nil) }
  # Not flagged, not decided by an admin, and never scored by Jev.
  scope :without_spam_review, -> { where(spam_source: nil, spam_score: nil) }
  # Spam whose images are due for deletion (Event::SpamImages).
  scope :spam_images_expired, ->(now) do
    cutoff = now - SPAM_IMAGE_RETENTION
    operator_spam_marked_before(cutoff).or(automatic_spam_unedited_since(cutoff))
  end
  # Retention counts from the operator's decision: an automatic flag keeps its
  # earlier spam_at when an operator confirms it. spam_decided_at was
  # backfilled from spam_at for older marks; spam_at covers any gap.
  scope :operator_spam_marked_before, ->(cutoff) do
    where(spam_source: "operator").where("COALESCE(events.spam_decided_at, events.spam_at) < ?", cutoff)
  end
  # Flagged by the Ruby rules or Jev before the cutoff and not edited since.
  # Every title or description edit touches updated_at (Action Text touches
  # the event) and re-runs the check, which keeps or clears the flag, so an
  # organizer still fixing a wrongly flagged event keeps its images. Jev flags
  # with update_columns, which sets spam_at without touching updated_at, hence
  # both. Cleared events and events edited out of spam have another
  # spam_source and never match.
  scope :automatic_spam_unedited_since, ->(cutoff) do
    where(spam_source: "automatic", spam_at: ...cutoff, updated_at: ...cutoff)
  end

  normalizes :time_zone, with: ->(time_zone) { time_zone.presence }

  before_validation :apply_submitted_schedule, if: :schedule_submitted?
  before_create :set_admin_token
  before_save :apply_spam_check, if: :spam_check_needed?
  after_save -> { RecentEventCreation.record_spam!(self) }, if: :became_spam?
  before_save :forget_spam_decision, if: :cleared_text_changed?
  after_commit :review_spam_later, on: %i[create update], if: -> { @spam_review_pending }
  after_rollback { @spam_review_pending = false }

  validates :title, presence: true
  validate :title_within_limit, if: :will_save_change_to_title?
  validate :description_within_limits, if: -> { rich_text_body&.changed? }
  validates :date, presence: true
  validates :published, inclusion: { in: [ true, false ] }
  validate :schedule_columns_are_complete, unless: :schedule_submitted?
  validate :time_zone_is_known
  validate :schedule_ends_after_it_starts
  validate :schedule_uses_event_date

  def spam?
    spam_at.present?
  end

  # The save that just happened made the event spam: it was not before, or
  # it was created as spam.
  def became_spam?
    saved_change_to_spam_at? && spam?
  end

  # Marked by an operator; final, and the organizer loses access.
  def spam_locked?
    spam_source == "operator"
  end

  # Marked by Event::SpamCheck; the organizer can edit the event to clear it.
  def flagged_as_spam?
    spam_source == "automatic"
  end

  # Flagged automatically with enough certainty (see CONFIDENT_SPAM_REASONS)
  # that the organizer's pages hide the verdict. Runs the Ruby rules for
  # automatic flags, so it is computed on demand, only on organizer and
  # creator page views.
  def confidently_spam?
    flagged_as_spam? && (spam_verdict_hidden? || confident_spam_signals?(spam_score, title, spam_check_html))
  end

  # An operator decided this is not spam; automatic checks leave it alone.
  def cleared_of_spam?
    spam_source == "cleared"
  end

  # Events the Ruby rules let through and no operator has decided on get a
  # second opinion from Event::SpamReview, once per text: every title or
  # description edit resets spam_score (apply_spam_check), so a score means
  # Jev already judged the current text. This only spares calls for reviews
  # queued behind one already done; the organizer rate limit bounds the rest.
  def spam_review_needed?
    spam_source.nil? && spam_score.nil? && Event::SpamReview.enabled?
  end

  def timed?
    starts_at.present?
  end

  def schedule_enabled=(value)
    @schedule_submitted = true
    @schedule_enabled = value.to_s.present? ? ActiveModel::Type::Boolean.new.cast(value) : nil
  end

  def schedule_enabled?
    return @schedule_enabled unless @schedule_enabled.nil?

    timed? || start_time.present? || end_time.present?
  end

  def start_time=(value)
    @schedule_submitted = true
    @start_time = value
  end

  def end_time=(value)
    @schedule_submitted = true
    @end_time = value
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

  def spam_check_needed?
    return false if spam_locked? || cleared_of_spam?

    new_record? || text_changed?
  end

  def apply_spam_check
    self.spam_verdict_hidden = true if confidently_spam_before_edit?
    self.spam_score = nil
    # Written even when this copy already reads nil: EventSpamReviewJob may
    # have scored the previous text since the event was loaded, and that score
    # would otherwise stand for the new text, which would then go unreviewed.
    spam_score_will_change!
    if Event::SpamCheck.spam?(title: title.to_s, html: spam_check_html)
      self.spam_at ||= Time.current
      self.spam_source = "automatic"
    elsif flagged_as_spam?
      self.spam_at = nil
      self.spam_source = nil
    end
    @spam_review_pending = spam_review_needed?
  end

  def spam_check_html
    rich_text_body&.body&.to_html.to_s
  end

  def confident_spam_signals?(score, title, html)
    return true if score && score >= CONFIDENT_SPAM_SCORE

    Event::SpamCheck.reasons(title: title.to_s, html: html).size >= CONFIDENT_SPAM_REASONS
  end

  # Once confident, the verdict stays hidden through later edits: otherwise
  # the edit that drops below the bar would tell the spammer they were caught,
  # and which change mattered.
  def confidently_spam_before_edit?
    return false if new_record? || spam_source_was != "automatic" || spam_verdict_hidden?

    confident_spam_signals?(spam_score_was, title_was, rich_text_body&.body_was&.to_html.to_s)
  end

  def title_within_limit
    length = title.to_s.length
    return if length <= MAXIMUM_TITLE_LENGTH || length <= title_was.to_s.length

    errors.add(:title, :too_long, count: MAXIMUM_TITLE_LENGTH)
  end

  def description_within_limits
    body, previous_body = rich_text_body.body, rich_text_body.body_was

    length = description_length(body)
    if length > MAXIMUM_DESCRIPTION_LENGTH && length > description_length(previous_body)
      errors.add(:body, "The description can be at most #{MAXIMUM_DESCRIPTION_LENGTH.to_fs(:delimited)} characters " \
                        "of text; it has #{length.to_fs(:delimited)}. Shorten it and try again.")
    end

    images_size = embedded_images_size(body)
    if images_size > MAXIMUM_IMAGES_SIZE && images_size > embedded_images_size(previous_body)
      errors.add(:body, IMAGES_TOO_LARGE)
    end
  end

  def description_length(content)
    content.present? ? Event::SpamCheck.visible_text(content.to_html).length : 0
  end

  # Bytes of the images the description embeds, each blob counted once:
  # Action Text uploads, and images referenced only by an Active Storage URL
  # (the former Trix uploader), both by their stored blob size. The submitted
  # filesize attribute is never trusted. Other remote images and data: URIs use
  # no storage here.
  def embedded_images_size(content)
    return 0 if content.blank?

    content.attachments.each_with_object({}) do |attachment, sizes|
      blob = attachment.attachable
      if !blob.is_a?(ActiveStorage::Blob) && attachment.node["sgid"].blank?
        signed_id = attachment.node["url"].to_s[LEGACY_UPLOAD_URL, 1]
        blob = signed_id && ActiveStorage::Blob.find_signed(CGI.unescape(signed_id))
      end
      sizes[blob.id] = blob.byte_size if blob.is_a?(ActiveStorage::Blob)
    end.values.sum
  end

  def text_changed?
    will_save_change_to_title? || rich_text_body&.changed?
  end

  # A cleared event's organizer can still edit it; the admin's decision no
  # longer covers the new text, so it stops being a "not spam" example.
  def cleared_text_changed?
    persisted? && cleared_of_spam? && spam_decided_at.present? && text_changed?
  end

  def forget_spam_decision
    self.spam_decided_at = nil
  end

  def review_spam_later
    @spam_review_pending = false
    EventSpamReviewJob.perform_later(id)
  end

  def schedule_submitted?
    @schedule_submitted
  end

  def apply_submitted_schedule
    self.starts_at = nil
    self.ends_at = nil

    unless schedule_enabled?
      self.time_zone = nil
      return
    end

    if start_time.blank? && end_time.blank?
      self.time_zone = nil
      return
    end

    self.time_zone = time_zone.presence
    errors.add(:start_time, :blank) if start_time.blank?
    errors.add(:end_time, :blank) if end_time.blank?

    zone = schedule_zone

    if time_zone.blank?
      errors.add(:time_zone, "can't be blank")
    elsif !zone
      errors.add(:time_zone, "isn't recognized")
    end
    return unless date && zone && start_time.present? && end_time.present?

    self.starts_at = schedule_time(start_time, zone, :start_time)
    self.ends_at = schedule_time(end_time, zone, :end_time)
  end

  def schedule_time(value, zone, attribute)
    match = TIME_PATTERN.match(value.to_s.strip)
    hour = match && Integer(match[:hour], 10, exception: false)
    minute = match && Integer(match[:minute] || "0", 10, exception: false)
    meridiem = match && match[:meridiem]&.delete(".")&.downcase
    twelve_hour_clock = meridiem || (hour&.between?(1, 12) && !match[:hour].start_with?("0"))

    hour = twelve_hour_clock_hour(hour, meridiem) if twelve_hour_clock

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

  def twelve_hour_clock_hour(hour, meridiem)
    return unless hour.between?(1, 12)

    return hour % 12 if meridiem&.start_with?("a")

    (hour % 12) + 12
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

    value.in_time_zone(zone).to_fs(:event_time)
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
