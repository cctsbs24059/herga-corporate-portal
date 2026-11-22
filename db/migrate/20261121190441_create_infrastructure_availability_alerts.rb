
# frozen_string_literal: true

class CreateInfrastructureAvailabilityAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :infrastructure_availability_alerts do |t|
      t.references :infrastructure_asset, null: false, foreign_key: true
      t.references :acknowledged_by, null: true, foreign_key: { to_table: :users }

      t.string :status, null: false, default: "Active"

      t.datetime :first_detected_at, null: false
      t.datetime :last_observed_at, null: false
      t.datetime :acknowledged_at
      t.datetime :cleared_at

      t.decimal :last_availability_percentage,
                precision: 6, scale: 2

      t.decimal :threshold_percentage,
                null: false, precision: 6, scale: 2

      t.datetime :assessment_period_end, null: false

      t.timestamps
    end

    add_index :infrastructure_availability_alerts,
              [:infrastructure_asset_id],
              unique: true,
              where: "status IN ('Active', 'Acknowledged')",
              name: "index_availability_alerts_one_unresolved_per_asset"

    add_index :infrastructure_availability_alerts,
              [:status, :last_observed_at],
              name: "index_availability_alerts_status_observed"
  end
end
