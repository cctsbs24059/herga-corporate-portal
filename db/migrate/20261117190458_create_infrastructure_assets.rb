
class CreateInfrastructureAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :infrastructure_assets do |t|
      t.string :hostname, null: false
      t.string :fqdn
      t.string :ip_address

      t.string :asset_type, null: false
      t.string :operating_system
      t.string :operating_system_version

      t.string :environment, null: false, default: "Production"
      t.string :location
      t.string :business_function

      t.string :status, null: false, default: "Active"
      t.string :source, null: false, default: "Manual"

      t.string :ad_object_guid
      t.string :ad_distinguished_name
      t.datetime :last_ad_sync_at

      t.text :description
      t.text :notes

      t.timestamps
    end

    add_index :infrastructure_assets, :hostname
    add_index :infrastructure_assets, :asset_type
    add_index :infrastructure_assets, :environment
    add_index :infrastructure_assets, :status
    add_index :infrastructure_assets, :source

    add_index :infrastructure_assets,
              :ad_object_guid,
              unique: true

    add_index :infrastructure_assets,
              "LOWER(fqdn)",
              unique: true,
              where: "fqdn IS NOT NULL AND fqdn <> ''",
              name: "index_infrastructure_assets_on_lower_fqdn"
  end
end

