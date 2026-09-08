class Rsvp < ApplicationRecord
  include Hashid::Rails

  RESPONSES = [
    :yes,
    :maybe,
    :no
  ]

  belongs_to :event

  validates :name, presence: true
  validates :response, presence: true, inclusion: { in: RESPONSES.map(&:to_s) }

  # Use this to avoid including new (unsaved) records
  scope :persisted, -> { where.not(id: nil) }

  def session_key
    [:event, event_id, :rsvp, id].join(':')
  end
end
