class AddActivationWindowToCoconiqueSafetyCheckSettings < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:coconique_safety_check_settings, :enabled_since)
      add_column :coconique_safety_check_settings, :enabled_since, :datetime
    end

    unless column_exists?(:coconique_safety_check_settings, :disabled_at)
      add_column :coconique_safety_check_settings, :disabled_at, :datetime
    end

    add_index :coconique_safety_check_settings, :enabled_since unless index_exists?(:coconique_safety_check_settings, :enabled_since)

    execute <<~SQL.squish
      UPDATE coconique_safety_check_settings
      SET enabled_since = COALESCE(created_at, NOW())
      WHERE enabled = TRUE
        AND mode <> 0
        AND enabled_since IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE coconique_safety_check_settings
      SET disabled_at = COALESCE(updated_at, NOW())
      WHERE (enabled = FALSE OR mode = 0)
        AND disabled_at IS NULL
    SQL
  end

  def down
    remove_index :coconique_safety_check_settings, :enabled_since if index_exists?(:coconique_safety_check_settings, :enabled_since)
    remove_column :coconique_safety_check_settings, :disabled_at if column_exists?(:coconique_safety_check_settings, :disabled_at)
    remove_column :coconique_safety_check_settings, :enabled_since if column_exists?(:coconique_safety_check_settings, :enabled_since)
  end
end
