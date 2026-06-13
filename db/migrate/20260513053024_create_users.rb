class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.datetime :email_verified_at
      t.integer :status, null: false, default: 0
      t.datetime :last_login_at

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :status
  end
end