class AddEmailChangeFieldsToEmailVerifications < ActiveRecord::Migration[8.1]
  def change
    add_column :email_verifications, :purpose, :string, default: "email_verification", null: false
    add_column :email_verifications, :pending_email, :string

    add_index :email_verifications, :purpose
    add_index :email_verifications, :pending_email
  end
end
