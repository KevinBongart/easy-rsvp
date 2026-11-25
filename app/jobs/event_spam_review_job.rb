# Second opinion for events the Ruby rules let through. Runs after the save so
# creating an event never waits on TypeSafe, and fails open: any API error
# leaves the event up. Each TypeSafe call costs credits, and every text edit
# queues a job, so a job finding the event already scored for its current text
# (spam_review_needed?) skips it: a backlog of queued reviews collapses to one
# call. Each text version that gets reviewed still costs a call; the organizer
# rate limit is what bounds the total.
class EventSpamReviewJob < ApplicationJob
  def perform(event_id)
    event = Event.find_by(id: event_id)
    return unless event&.spam_review_needed?

    review = Event::SpamReview.new(event)
    page = begin
      review.page
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { event_id: event.id })
      return
    end
    score = review.score(page:)
    return if score.nil?

    changes = { spam_score: score }
    changes.merge!(spam_at: Time.current, spam_source: "automatic") if score >= Event::SpamReview::THRESHOLD
    # Write only if Jev judged the text the event still has, and neither an
    # admin nor another job has decided meanwhile. A text edit queued its own review; other edits (date,
    # publication) do not change the answer.
    event.with_lock do
      next unless event.spam_review_needed? && review.page == page

      event.update_columns(changes)
      RecentEventCreation.record_spam!(event) if event.spam?
    end
  end
end
