class Rsvp < ApplicationRecord
  RESPONSES = [
    :yes,
    :maybe,
    :no
  ]

  belongs_to :event

  validates :name, presence: true
  validates :response, presence: true
end
