# frozen_string_literal: true

class CreateInfrastructureAvailabilityAssessments < ActiveRecord::Migration[8.1]
  def change
    create_table :infrastructure_availability_assessments do |t|
      t.references :infrastructure_asset, null: false, foreign_key: true, index: false
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.integer :total_checks, null: false, default: 0
      t.integer :reachable_checks, null: false, default: 0
      t.integer :unreachable_checks, null: false, default: 0
      t.integer :unknown_checks, null: false, default: 0
      t.decimal :availability_percentage, precision: 6, scale: 2
      t.decimal :threshold_percentage, precision: 6, scale: 2, null: false
      t.string :assessment_status, null: false
      t.timestamps
    end

    add_index :infrastructure_availability_assessments,
              [:infrastructure_asset_id, :period_start, :period_end],
              unique: true, name: "index_infra_availability_assessments_unique_period"
    add_index :infrastructure_availability_assessments, [:period_end, :assessment_status],
              name: "index_infra_availability_assessments_reporting"
  end
end
