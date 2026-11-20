# Second opinion for events the Ruby rules let through. Runs after the save so
# creating an event never waits on TypeSafe, and fails open: any API error
# leaves the event up.
class EventSpamReviewJob < ApplicationJob
  def perform(event_id)
    event = Event.find_by(id: event_id)
    return unless event&.spam_review_needed?

    page = begin
      Event::SpamReview.page(event)
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { event_id: event.id })
      return
    end
    score = Event::SpamReview.score(event, page:)
    return if score.nil?

    changes = { spam_score: score }
    changes.merge!(spam_at: Time.current, spam_source: "automatic") if score >= Event::SpamReview::THRESHOLD
    # Write only if Jev judged the text the event still has and no admin has
    # decided meanwhile. A text edit queued its own review; other edits (date,
    # publication) do not change the answer.
    event.with_lock do
      next unless event.spam_review_needed? && Event::SpamReview.page(event) == page

      event.update_columns(changes)
      RecentEventCreation.record_spam!(event) if event.spam?
    end
  end
end
