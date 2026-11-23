# frozen_string_literal: true

class CreateInfrastructureNotificationLegalHoldEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :infrastructure_notification_legal_hold_events do |t|
      t.references :notification_legal_hold, null: false,
                   foreign_key: { to_table: :infrastructure_notification_legal_holds },
                   index: { name: "idx_herga_hold_events_hold" }
      t.string :action, null: false
      t.string :actor, null: false
      t.text :justification, null: false
      t.datetime :created_at, null: false
    end
    add_check_constraint :infrastructure_notification_legal_hold_events,
                         "length(btrim(justification)) > 0 AND length(btrim(actor)) > 0",
                         name: "chk_herga_hold_event_evidence"
    execute <<~SQL
      CREATE FUNCTION herga_prevent_legal_hold_event_mutation()
      RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'Legal hold audit events are append-only';
      END;
      $$;
      CREATE TRIGGER herga_legal_hold_events_append_only
      BEFORE UPDATE OR DELETE ON infrastructure_notification_legal_hold_events
      FOR EACH ROW EXECUTE FUNCTION herga_prevent_legal_hold_event_mutation();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS herga_legal_hold_events_append_only ON infrastructure_notification_legal_hold_events"
    execute "DROP FUNCTION IF EXISTS herga_prevent_legal_hold_event_mutation()"
    drop_table :infrastructure_notification_legal_hold_events
  end
end
