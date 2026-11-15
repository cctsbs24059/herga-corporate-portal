# Creates the database table used to store HERGA applications.
class CreatePortalApplications < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_applications do |t| # Create the portal_applications table.
      t.string :name     # Application display name, e.g. PXtool.
      t.text :description  # Description displayed on application cards.
      t.string :url  # URL used to launch the application.
      t.string :category  # Application category, e.g. IT Operations.
      t.string :icon  # Icon identifier for the application.
          # Determines whether the application is visible.
      t.boolean :active, default: true, null: false  # New applications are hidden until activated.
      t.integer :position, default: 0, null: false   # Determines the order in which applications appear.

      t.timestamps
    end
    # Improve filtering and ordering of application records.
    add_index :portal_applications, [:active, :position]
  end
end
