class CreateUserSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :user_sessions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :restrict }
      t.string :token_digest, null: false, limit: 64
      t.string :csrf_token_digest, null: false, limit: 64
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :user_sessions, :token_digest, unique: true
  end
end
