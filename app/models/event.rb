class Event < ApplicationRecord
  include Hashid::Rails

  before_create :set_admin_token

  def to_param
    "#{hashid}-#{title.parameterize}"
  end


  private

  def set_admin_token
    self.admin_token = SecureRandom.uuid
  end
end
