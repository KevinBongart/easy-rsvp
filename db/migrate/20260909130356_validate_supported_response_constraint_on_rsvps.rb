class ValidateSupportedResponseConstraintOnRsvps < ActiveRecord::Migration[8.1]
  def up
    validate_check_constraint :rsvps, name: "rsvps_supported_response"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "PostgreSQL cannot mark a validated constraint NOT VALID without recreating it"
  end
end
