class DropQuarantinedUnrelatedTables < ActiveRecord::Migration[8.1]
  TABLES = %w[
    quarantined_20260915_action_text_rich_texts
    quarantined_20260915_admins
    quarantined_20260915_card_games
    quarantined_20260915_card_players
    quarantined_20260915_cards
    quarantined_20260915_categories
    quarantined_20260915_entries
    quarantined_20260915_games
    quarantined_20260915_gifts
    quarantined_20260915_imports
    quarantined_20260915_line_items
    quarantined_20260915_lists
    quarantined_20260915_options
    quarantined_20260915_packs
    quarantined_20260915_payments
    quarantined_20260915_players
    quarantined_20260915_records
    quarantined_20260915_rounds
    quarantined_20260915_submissions
  ].freeze

  def up
    quoted_tables = TABLES.map { |table| connection.quote_table_name(table) }
    execute "DROP TABLE IF EXISTS #{quoted_tables.join(', ')}"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      'The quarantined tables and their data cannot be restored by a rollback'
  end
end
