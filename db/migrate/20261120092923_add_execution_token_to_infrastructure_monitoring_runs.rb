class AddExecutionTokenToInfrastructureMonitoringRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :infrastructure_monitoring_runs,
               :execution_token,
               :string

    add_index :infrastructure_monitoring_runs,
              :execution_token,
              unique: true,
              name: "index_monitoring_runs_on_execution_token"
  end
end