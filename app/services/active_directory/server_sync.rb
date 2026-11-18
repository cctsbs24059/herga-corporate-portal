
# frozen_string_literal: true

require "net/ldap"
require "openssl"

module ActiveDirectory
  class ServerSync
    class SyncError < StandardError; end

    ATTRIBUTES = %w[
      objectGUID
      cn
      dNSHostName
      operatingSystem
      operatingSystemVersion
      description
      distinguishedName
    ].freeze

    Result = Struct.new(
      :discovered,
      :created,
      :updated,
      :skipped,
      :conflicts,
      keyword_init: true
    )

    def initialize
      @ldap = ActiveDirectoryAuthenticator.connection(
        username: ENV.fetch("HERGA_AD_SERVICE_USER"),
        password: ENV.fetch("HERGA_AD_SERVICE_PASSWORD")
      )
    end

    def call
      servers = discover_servers

      result = Result.new(
        discovered: servers.size,
        created: 0,
        updated: 0,
        skipped: 0,
        conflicts: []
      )

      # Apply changes atomically after successful LDAP discovery.
      InfrastructureAsset.transaction do
        servers.each do |server|
          synchronize_server(server, result)
        end
      end

      result
    rescue ActiveRecord::ActiveRecordError => e
      raise SyncError, "Database synchronization failed: #{e.message}"
    end

    private

    def discover_servers
      unless @ldap.bind
        raise SyncError, "Active Directory service account bind failed."
      end

      filter =
        Net::LDAP::Filter.eq("objectCategory", "computer") &
        Net::LDAP::Filter.eq("objectClass", "computer") &
        Net::LDAP::Filter.eq("operatingSystem", "*Windows Server*")

      entries = @ldap.search(
        base: ActiveDirectoryAuthenticator::BASE_DN,
        filter: filter,
        attributes: ATTRIBUTES,
        paged_searches: true
      )

      operation = @ldap.get_operation_result

      unless operation.code == 0 && entries.is_a?(Array)
        raise SyncError,
              "Active Directory discovery failed: #{operation.message}"
      end

      servers = entries.map do |entry|
        guid = decode_guid(entry[:objectguid].first)

        hostname = attribute(entry, :cn).strip
        fqdn = attribute(entry, :dnshostname).strip.downcase

        if guid.blank? || hostname.blank?
          raise SyncError,
                "AD computer record is missing an objectGUID or hostname."
        end

        {
          guid: guid,
          hostname: hostname.upcase,
          fqdn: fqdn.presence,
          operating_system: attribute(entry, :operatingsystem),
          operating_system_version: attribute(
            entry, :operatingsystemversion
          ),
          description: attribute(entry, :description),
          dn: entry.dn.to_s
        }
      end

      if servers.map { |s| s[:guid] }.uniq.size != servers.size
        raise SyncError, "Duplicate objectGUID values in LDAP results."
      end

      servers
    rescue Net::LDAP::Error, OpenSSL::SSL::SSLError,
           IOError, SystemCallError, Timeout::Error => e
      raise SyncError, "Active Directory discovery failed: #{e.message}"
    end

    def synchronize_server(server, result)
      asset = InfrastructureAsset.find_by(
        ad_object_guid: server[:guid]
      )

      if asset && asset.source != "Active Directory"
        record_conflict(result, server, "GUID belongs to manual asset")
        return
      end

      # Never overwrite a different asset sharing the same FQDN.
      if server[:fqdn].present?
        matching_fqdn = InfrastructureAsset
          .where("LOWER(fqdn) = ?", server[:fqdn])
          .where.not(id: asset&.id)
          .first

        if matching_fqdn
          record_conflict(result, server, "FQDN already registered")
          return
        end
      end

      # Avoid duplicating manually registered assets without FQDNs.
      unless asset
        matching_hostname = InfrastructureAsset
          .where("LOWER(hostname) = ?", server[:hostname].downcase)
          .first

        if matching_hostname
          record_conflict(result, server, "Hostname already registered")
          return
        end
      end

      attributes = {
        hostname: server[:hostname],
        fqdn: server[:fqdn],
        operating_system: server[:operating_system],
        operating_system_version: server[:operating_system_version],
        ad_distinguished_name: server[:dn],
        last_ad_sync_at: Time.current
      }

      if asset
        asset.update!(attributes)
        result.updated += 1
      else
        InfrastructureAsset.create!(
          attributes.merge(
            asset_type: "Windows Server",
            environment: "Production",
            status: "Active",
            source: "Active Directory",
            ad_object_guid: server[:guid],
            description: server[:description]
          )
        )

        result.created += 1
      end
    end

    def record_conflict(result, server, reason)
      result.skipped += 1
      result.conflicts << "#{server[:hostname]}: #{reason}"
    end

    def attribute(entry, name)
      entry[name].first.to_s
    end

    # AD objectGUID is a 16-byte binary UUID with mixed-endian fields.
    def decode_guid(raw)
      return nil unless raw && raw.bytesize == 16

      bytes = raw.unpack("C16")

      a = bytes[0, 4].reverse.pack("C*").unpack1("H*")
      b = bytes[4, 2].reverse.pack("C*").unpack1("H*")
      c = bytes[6, 2].reverse.pack("C*").unpack1("H*")
      d = bytes[8, 2].pack("C*").unpack1("H*")
      e = bytes[10, 6].pack("C*").unpack1("H*")

      "#{a}-#{b}-#{c}-#{d}-#{e}"
    end
  end
end
