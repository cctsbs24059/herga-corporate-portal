# frozen_string_literal: true

class CreateInfrastructureIncidents < ActiveRecord::Migration[8.1]
  def change
    create_table :infrastructure_incidents do |t|
      t.references :infrastructure_asset, null: false, foreign_key: true
      t.string :incident_type, null: false, default: "ICMP Connectivity"
      t.string :severity, null: false, default: "Critical"
      t.string :status, null: false, default: "Open"
      t.text :description
      t.datetime :first_detected_at, null: false
      t.datetime :last_observed_at, null: false
      t.integer :consecutive_failures, null: false, default: 3
      t.datetime :resolved_at
      t.string :resolution_reason
      t.timestamps
    end

    add_index :infrastructure_incidents,
              [:infrastructure_asset_id, :incident_type],
              unique: true,
              where: "status = 'Open'",
              name: "index_infrastructure_incidents_one_open_per_asset_type"
    add_index :infrastructure_incidents, [:status, :last_observed_at],
              name: "index_infrastructure_incidents_on_status_and_observed"
  end
end
