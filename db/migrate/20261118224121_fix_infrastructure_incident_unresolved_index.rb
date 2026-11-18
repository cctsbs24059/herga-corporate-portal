
# frozen_string_literal: true

class FixInfrastructureIncidentUnresolvedIndex < ActiveRecord::Migration[8.1]
  OLD_INDEX = "index_infrastructure_incidents_one_open_per_asset_type"
  NEW_INDEX = "index_incidents_one_unresolved_per_asset_type"

  def up
    remove_index :infrastructure_incidents,
                 name: OLD_INDEX,
                 if_exists: true

    add_index :infrastructure_incidents,
              [:infrastructure_asset_id, :incident_type],
              unique: true,
              where: "status IN ('Open', 'Acknowledged')",
              name: NEW_INDEX
  end

  def down
    remove_index :infrastructure_incidents,
                 name: NEW_INDEX,
                 if_exists: true

    add_index :infrastructure_incidents,
              [:infrastructure_asset_id, :incident_type],
              unique: true,
              where: "status = 'Open'",
              name: OLD_INDEX
  end
end
