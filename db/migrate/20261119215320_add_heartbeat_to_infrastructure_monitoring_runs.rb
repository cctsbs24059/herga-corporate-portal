class AddHeartbeatToInfrastructureMonitoringRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :infrastructure_monitoring_runs,
               :heartbeat_at,
               :datetime
  end
end