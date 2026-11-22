
# frozen_string_literal: true

class CreateInfrastructureNotificationAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :infrastructure_notification_attempts do |t|
      t.references :infrastructure_notification,
                   null: false,
                   foreign_key: true,
                   index: {
                     name: "idx_notification_attempts_notification"
                   }

      t.string :status, null: false

      t.datetime :attempted_at, null: false

      t.string :provider_message_id

      t.string :error_class

      t.text :error_message

      t.timestamps
    end

    add_index :infrastructure_notification_attempts,
              :attempted_at,
              name: "idx_notification_attempts_attempted_at"

    add_index :infrastructure_notification_attempts,
              :status,
              name: "idx_notification_attempts_status"
  end
end
