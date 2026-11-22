# frozen_string_literal: true

class AlignInfrastructureNotificationSchema < ActiveRecord::Migration[8.1]
  def up
    unless table_exists?(:infrastructure_notifications)
      raise "Missing infrastructure_notifications table. Apply the notifications phase first."
    end

    change_table :infrastructure_notifications do |t|
      t.string :source_type unless column_exists?(:infrastructure_notifications, :source_type)
      t.bigint :source_id unless column_exists?(:infrastructure_notifications, :source_id)
      t.datetime :occurred_at unless column_exists?(:infrastructure_notifications, :occurred_at)
      t.datetime :attempted_at unless column_exists?(:infrastructure_notifications, :attempted_at)
      t.datetime :accepted_at unless column_exists?(:infrastructure_notifications, :accepted_at)
    end

    # Preserve existing values if the alternate schema has already been populated.
    if column_exists?(:infrastructure_notifications, :notifiable_type)
      execute <<~SQL
        UPDATE infrastructure_notifications
        SET source_type = notifiable_type
        WHERE source_type IS NULL AND notifiable_type IS NOT NULL
      SQL
    end
    if column_exists?(:infrastructure_notifications, :notifiable_id)
      execute <<~SQL
        UPDATE infrastructure_notifications
        SET source_id = notifiable_id
        WHERE source_id IS NULL AND notifiable_id IS NOT NULL
      SQL
    end
    if column_exists?(:infrastructure_notifications, :event_occurred_at)
      execute <<~SQL
        UPDATE infrastructure_notifications
        SET occurred_at = event_occurred_at
        WHERE occurred_at IS NULL AND event_occurred_at IS NOT NULL
      SQL
    end
    if column_exists?(:infrastructure_notifications, :last_attempt_at)
      execute <<~SQL
        UPDATE infrastructure_notifications
        SET attempted_at = last_attempt_at
        WHERE attempted_at IS NULL AND last_attempt_at IS NOT NULL
      SQL
    end
    if column_exists?(:infrastructure_notifications, :sent_at)
      execute <<~SQL
        UPDATE infrastructure_notifications
        SET accepted_at = sent_at
        WHERE accepted_at IS NULL AND sent_at IS NOT NULL
      SQL
    end

    # The alternate migration marked these columns NOT NULL. The original
    # notification reconciler writes source_* and occurred_at instead.
    # Retain the alternate columns for audit, but allow new rows to omit them.
    %i[notifiable_type notifiable_id event_occurred_at].each do |column|
      if column_exists?(:infrastructure_notifications, column)
        change_column_null :infrastructure_notifications, column, true
      end
    end

    unless table_exists?(:infrastructure_notification_attempts)
      create_table :infrastructure_notification_attempts do |t|
        t.references :infrastructure_notification, null: false, foreign_key: true,
                     index: { name: 'idx_infrastructure_notification_attempts_parent' }
        t.string :status, null: false
        t.text :error_message
        t.datetime :attempted_at, null: false
        t.timestamps
      end
    end

    unless column_exists?(:infrastructure_notification_attempts, :error_message)
      add_column :infrastructure_notification_attempts, :error_message, :text
    end
    unless column_exists?(:infrastructure_notification_attempts, :attempted_at)
      add_column :infrastructure_notification_attempts, :attempted_at, :datetime
    end
    unless index_exists?(:infrastructure_notifications, [:source_type, :source_id])
      add_index :infrastructure_notifications, [:source_type, :source_id]
    end
  end

  def down
    # Deliberately non-destructive: the migration may have populated previously
    # existing notification rows, and removing columns could lose audit data.
  end
end
