
# frozen_string_literal: true

class AddManagementToInfrastructureIncidents < ActiveRecord::Migration[8.1]
  def change
    change_table :infrastructure_incidents do |t|
      t.references :assigned_to, foreign_key: { to_table: :users }
      t.references :acknowledged_by, foreign_key: { to_table: :users }
      t.references :resolved_by, foreign_key: { to_table: :users }

      t.datetime :acknowledged_at
      t.text :resolution_note

      # Suppresses reopening until a successful connectivity
      # observation establishes a new failure sequence.
      t.boolean :suppress_until_recovery, default: false, null: false
    end

    create_table :infrastructure_incident_events do |t|
      t.references :infrastructure_incident,
                   null: false,
                   foreign_key: true

      t.references :user, foreign_key: true

      t.string :event_type, null: false
      t.text :details

      t.timestamps
    end

    add_index :infrastructure_incident_events,
              [:infrastructure_incident_id, :created_at],
              name: "index_incident_events_on_incident_and_created"
  end
end
