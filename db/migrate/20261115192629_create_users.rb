class CreateUsers < ActiveRecord::Migration[8.1]
# Stores application identity information for AD users.
#
# No password column is created because passwords are
# validated by Active Directory, not PostgreSQL.
  def change
    create_table :users do |t|
      t.string :username, null: false
      t.string :email
      t.string :display_name
      t.text :ad_dn

      # This is a cached AD-derived role, not the authority
      # for granting administrative permissions.
      t.boolean :admin, default: false, null: false

      t.timestamps
    end
    # Prevent duplicate local accounts for one AD username.
    add_index :users, :username, unique: true
  end
end
