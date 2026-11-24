# One row recording whether Event::SpamReview (Jev) is answering, so the admin
# dashboard can show when it stopped. Reviews fail open, so without this an
# outage only shows up as events silently published unreviewed. Kept in the
# database because deploys and restarts clear process memory.
class CreateSpamReviewStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :spam_review_statuses do |t|
      t.datetime :last_succeeded_at
      t.datetime :last_failed_at
      t.datetime :failing_since
      t.integer :consecutive_failures, default: 0, null: false
      t.string :last_error
      t.check_constraint "id = 1", name: "spam_review_statuses_single_row"
    end
  end
end
