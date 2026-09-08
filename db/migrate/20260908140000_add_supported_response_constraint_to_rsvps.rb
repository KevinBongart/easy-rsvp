class AddSupportedResponseConstraintToRsvps < ActiveRecord::Migration[8.1]
  def change
    # Protect new writes without scanning or rewriting historical responses.
    # Validate the existing rows separately after any invalid values are reviewed.
    add_check_constraint :rsvps,
      "response IS NOT NULL AND response IN ('yes', 'maybe', 'no')",
      name: "rsvps_supported_response",
      validate: false
  end
end
