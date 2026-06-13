class CreateTermsAcceptances < ActiveRecord::Migration[8.0]
  def change
    create_table :terms_acceptances do |t|
      t.references :user, null: false, foreign_key: true
      t.string :app_key, null: false
      t.string :terms_version, null: false
      t.string :privacy_version, null: false
      t.datetime :accepted_at, null: false
      t.string :ip_address
      t.text :user_agent

      t.timestamps
    end

    add_index :terms_acceptances, [:user_id, :app_key]
    add_index :terms_acceptances, [:app_key, :terms_version, :privacy_version], name: "index_terms_acceptances_on_versions"
    add_index :terms_acceptances, :accepted_at
  end
end