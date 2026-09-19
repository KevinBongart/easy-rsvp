class ApplicationController < ActionController::Base
  private

  def event_hashid_from_param(parameterized_id)
    parameterized_id.to_s.split('-', 2).first
  end
end
