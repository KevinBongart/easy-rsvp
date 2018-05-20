class Rsvp < ApplicationRecord
  include Hashid::Rails

  RESPONSES = [
    :yes,
    :maybe,
    :no
  ]

  belongs_to :event

  validates :name, presence: true
  validates :response, presence: true

  def session_key
    [:event, event_id, :rsvp, id].join(':')
  end
end
