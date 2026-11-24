# Whether Jev (Event::SpamReview) is answering. Reviews fail open, so an
# outage (a revoked key, no credits left, TypeSafe down) otherwise only shows
# as events quietly published without a score. A single row, written after
# each review by EventSpamReviewJob, off the request path, and read by the
# admin dashboard. It never holds event content or the API key.
class SpamReviewStatus < ApplicationRecord
  ROW_ID = 1
  ERROR_SUMMARY_LENGTH = 200
  # A review fails at most 35 seconds after it starts (the HTTP timeouts in
  # Event::SpamReview#post), but a burst of events queues behind the job
  # threads, so the first failed events can be minutes older than the failure.
  FIRST_FAILURE_LEEWAY = 5.minutes

  # The stored status, or a blank one before the first review.
  def self.current
    find_by(id: ROW_ID) || new
  end

  # One statement without a lock: a success only has to end the streak.
  def self.record_success!
    upsert({ id: ROW_ID, last_succeeded_at: Time.current, failing_since: nil, consecutive_failures: 0 }, unique_by: :id)
  end

  # Returns true when this failure started the streak; the row lock makes
  # exactly one of several concurrent failures see that.
  def self.record_failure!(error_summary)
    transaction do
      status = create_or_find_by!(id: ROW_ID)
      status.lock!
      started_failing = !status.failing?
      status.update!(
        failing_since: status.failing_since || Time.current,
        consecutive_failures: status.consecutive_failures + 1,
        last_failed_at: Time.current,
        last_error: error_summary.truncate(ERROR_SUMMARY_LENGTH)
      )
      started_failing
    end
  end

  # Set from the first failure after a success until the next success.
  def failing?
    failing_since.present?
  end

  # Events created while Jev was failing that it never scored and no rule or
  # admin judged: they went out without a second opinion.
  def unreviewed_events_count
    return 0 unless failing?

    Event.without_spam_review.where(created_at: unreviewed_since..).count
  end

  # The earlier of the last success and just before the first failure: with
  # concurrent reviews, a success can land after an event whose review then
  # fails. Events Jev scored in that stretch have a score and are not counted.
  def unreviewed_since
    [ last_succeeded_at, failing_since - FIRST_FAILURE_LEEWAY ].compact.min if failing?
  end
end
