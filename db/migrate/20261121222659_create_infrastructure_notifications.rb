
# frozen_string_literal: true

class CreateInfrastructureNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :infrastructure_notifications do |t|
      # Source event
      t.string :event_key, null: false
      t.string :event_type, null: false

      # Related incident or availability alert
      t.references :notifiable,
                   polymorphic: true,
                   null: false,
                   index: true

      # Email recipient
      t.string :recipient, null: false

      # Notification lifecycle
      t.string :status, null: false, default: "Pending"

      # Escalation management
      t.integer :escalation_level, null: false, default: 0

      # Delivery tracking
      t.integer :attempt_count, null: false, default: 0
      t.datetime :last_attempt_at
      t.datetime :sent_at
      t.datetime :next_attempt_at

      # Delivery diagnostics
      t.text :last_error
      t.string :message_id

      # Event timestamps
      t.datetime :event_occurred_at, null: false

      t.timestamps
    end

    # Prevent duplicate notifications for the same event.
    add_index :infrastructure_notifications,
              :event_key,
              unique: true

    # Efficient administrator reporting.
    add_index :infrastructure_notifications,
              [:status, :created_at],
              name: "idx_infrastructure_notifications_status_created"

    # Escalation and delivery processing.
    add_index :infrastructure_notifications,
              [:status, :next_attempt_at],
              name: "idx_infrastructure_notifications_delivery"
  end
end
