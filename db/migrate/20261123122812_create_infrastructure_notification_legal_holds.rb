# frozen_string_literal: true

class CreateInfrastructureNotificationLegalHolds < ActiveRecord::Migration[8.1]
  def change
    create_table :infrastructure_notification_legal_holds do |t|
      t.bigint :infrastructure_notification_id, null: false
      t.string :reference, null: false
      t.text :reason, null: false
      t.string :placed_by, null: false
      t.datetime :placed_at, null: false
      t.string :released_by
      t.datetime :released_at
      t.timestamps
    end

    add_foreign_key :infrastructure_notification_legal_holds, :infrastructure_notifications,
                    column: :infrastructure_notification_id
    add_index :infrastructure_notification_legal_holds, :reference, unique: true,
              name: "idx_herga_legal_holds_reference"
    add_index :infrastructure_notification_legal_holds,
              [:infrastructure_notification_id, :released_at],
              name: "idx_herga_legal_holds_active"
    add_check_constraint :infrastructure_notification_legal_holds,
                         "(released_at IS NULL AND released_by IS NULL) OR (released_at IS NOT NULL AND released_by IS NOT NULL)",
                         name: "chk_herga_legal_hold_release"
  end
end
