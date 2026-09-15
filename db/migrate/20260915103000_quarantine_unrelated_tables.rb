class QuarantineUnrelatedTables < ActiveRecord::Migration[8.1]
  TABLES = %w[
    action_text_rich_texts
    admins
    card_games
    card_players
    cards
    categories
    entries
    games
    gifts
    imports
    line_items
    lists
    options
    packs
    payments
    players
    records
    rounds
    submissions
  ].freeze

  PREFIX = "quarantined_20260915_"

  def up
    TABLES.each do |table|
      quarantine_table = "#{PREFIX}#{table}"
      next unless table_exists?(table)

      raise "Refusing to overwrite #{quarantine_table}" if table_exists?(quarantine_table)

      rename_table table, quarantine_table
    end

    rename_action_text_index(
      "#{PREFIX}action_text_rich_texts",
      "index_action_text_rich_texts_uniqueness",
      "index_quarantined_20260915_action_text_rich_texts_uniqueness"
    )
  end

  def down
    rename_action_text_index(
      "#{PREFIX}action_text_rich_texts",
      "index_quarantined_20260915_action_text_rich_texts_uniqueness",
      "index_action_text_rich_texts_uniqueness"
    )

    TABLES.reverse_each do |table|
      quarantine_table = "#{PREFIX}#{table}"
      next unless table_exists?(quarantine_table)

      raise "Refusing to overwrite #{table}" if table_exists?(table)

      rename_table quarantine_table, table
    end
  end

  private

  def rename_action_text_index(table, old_name, new_name)
    return unless table_exists?(table) && index_name_exists?(table, old_name)

    rename_index table, old_name, new_name
  end
end
