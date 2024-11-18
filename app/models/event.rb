class Event < ApplicationRecord
  include Hashid::Rails

  has_many :rsvps

  before_create :set_admin_token

  validates :title, presence: true
  validates :date, presence: true

  def to_param
    "#{hashid}-#{title.parameterize}"
  end

  private

  def set_admin_token
    self.admin_token = SecureRandom.uuid
  end
end
