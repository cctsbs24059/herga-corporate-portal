
# frozen_string_literal: true

class CreateInfrastructureMonitoringTables < ActiveRecord::Migration[8.1]
  def change
    create_table :infrastructure_monitoring_runs do |t|
      t.string :status, null: false, default: "Queued"
      t.integer :total_assets, null: false, default: 0
      t.integer :processed_assets, null: false, default: 0
      t.integer :reachable_assets, null: false, default: 0
      t.integer :unreachable_assets, null: false, default: 0
      t.integer :unknown_assets, null: false, default: 0
      t.integer :failed_checks, null: false, default: 0

      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message

      t.timestamps
    end

    add_index :infrastructure_monitoring_runs,
              :status

    add_index :infrastructure_monitoring_runs,
              :created_at

    create_table :infrastructure_connectivity_results do |t|
      t.references :infrastructure_asset,
                   null: false,
                   foreign_key: true,
                   index: true

      t.references :infrastructure_monitoring_run,
                   null: true,
                   foreign_key: true,
                   index: true

      t.string :dns_status
      t.string :resolved_ip_address
      t.string :icmp_status
      t.float :icmp_response_ms
      t.text :connectivity_error
      t.datetime :checked_at, null: false

      t.timestamps
    end

    add_index :infrastructure_connectivity_results,
              [:infrastructure_asset_id, :checked_at],
              name: "index_connectivity_results_on_asset_and_checked_at"
  end
end
