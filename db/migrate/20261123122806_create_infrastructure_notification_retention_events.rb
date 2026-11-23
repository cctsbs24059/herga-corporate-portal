# frozen_string_literal: true

class CreateInfrastructureNotificationRetentionEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :infrastructure_notification_retention_events do |t|
      t.references :notification_retention_policy, null: false,
                   foreign_key: { to_table: :infrastructure_notification_retention_policies },
                   index: { name: "idx_herga_retention_events_policy" }
      t.string :action, null: false
      t.string :actor, null: false
      t.string :from_status
      t.string :to_status, null: false
      t.integer :policy_version, null: false
      t.datetime :created_at, null: false
    end

    # PostgreSQL enforces append-only behaviour, including for direct SQL UPDATE/DELETE.
    execute <<~SQL
      CREATE FUNCTION herga_prevent_retention_event_mutation()
      RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'Retention audit events are append-only';
      END;
      $$;
      CREATE TRIGGER herga_retention_events_append_only
      BEFORE UPDATE OR DELETE ON infrastructure_notification_retention_events
      FOR EACH ROW EXECUTE FUNCTION herga_prevent_retention_event_mutation();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS herga_retention_events_append_only ON infrastructure_notification_retention_events"
    execute "DROP FUNCTION IF EXISTS herga_prevent_retention_event_mutation()"
    drop_table :infrastructure_notification_retention_events
  end
end
