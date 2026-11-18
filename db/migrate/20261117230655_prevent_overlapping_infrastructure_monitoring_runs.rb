
# frozen_string_literal: true

class PreventOverlappingInfrastructureMonitoringRuns < ActiveRecord::Migration[8.1]
  def change
    add_index :infrastructure_monitoring_runs,
              "(CASE WHEN status IN ('Queued', 'Running') THEN 1 ELSE NULL END)",
              unique: true,
              name: "index_infrastructure_monitoring_runs_one_active"
  end
end
