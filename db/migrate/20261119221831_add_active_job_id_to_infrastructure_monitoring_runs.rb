class AddActiveJobIdToInfrastructureMonitoringRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :infrastructure_monitoring_runs,
               :active_job_id,
               :string

    add_index :infrastructure_monitoring_runs,
              :active_job_id,
              unique: true
  end
end