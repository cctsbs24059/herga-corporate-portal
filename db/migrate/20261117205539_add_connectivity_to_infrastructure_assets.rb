class AddConnectivityToInfrastructureAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :infrastructure_assets, :dns_status, :string
    add_column :infrastructure_assets, :resolved_ip_address, :string
    add_column :infrastructure_assets, :icmp_status, :string
    add_column :infrastructure_assets, :icmp_response_ms, :float
    add_column :infrastructure_assets, :last_connectivity_check_at, :datetime
    add_column :infrastructure_assets, :connectivity_error, :text
  end
end
