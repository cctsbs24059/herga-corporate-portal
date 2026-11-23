# frozen_string_literal: true

class CreateInfrastructureNotificationRetentionPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :infrastructure_notification_retention_policies do |t|
      t.string :name, null: false
      t.string :reference, null: false
      t.integer :retention_days, null: false, default: 365
      t.string :status, null: false, default: "Draft"
      t.integer :version, null: false, default: 1
      t.string :approved_by
      t.datetime :approved_at
      t.string :suspended_by
      t.datetime :suspended_at
      t.timestamps
    end

    add_index :infrastructure_notification_retention_policies, :reference, unique: true,
              name: "idx_herga_retention_policies_reference"
    add_check_constraint :infrastructure_notification_retention_policies,
                         "retention_days BETWEEN 30 AND 3650", name: "chk_herga_retention_days"
    add_check_constraint :infrastructure_notification_retention_policies,
                         "status IN ('Draft', 'Approved', 'Suspended')", name: "chk_herga_retention_status"
    add_check_constraint :infrastructure_notification_retention_policies,
                         "version >= 1", name: "chk_herga_retention_version"
  end
end
