
# frozen_string_literal: true

require "net/ldap"
require "openssl"
require "time"

module ActiveDirectory
  class ComputerDirectory
    BASE_DN = ActiveDirectoryAuthenticator::BASE_DN

    MAX_RESULTS = 500
    MAX_SEARCH_LENGTH = 100
    ACCOUNT_DISABLED = 0x0002

    WINDOWS_EPOCH_OFFSET = 116_444_736_000_000_000
    WINDOWS_TICKS_PER_SECOND = 10_000_000

    class DirectoryError < StandardError; end

    Computer = Struct.new(
      :name,
      :account_name,
      :dns_hostname,
      :description,
      :operating_system,
      :operating_system_version,
      :operating_system_service_pack,
      :enabled,
      :last_logon,
      :password_last_set,
      :when_created,
      :dn,
      keyword_init: true
    )

    COMPUTER_ATTRIBUTES = %w[
      cn
      sAMAccountName
      dNSHostName
      description
      operatingSystem
      operatingSystemVersion
      operatingSystemServicePack
      userAccountControl
      lastLogonTimestamp
      pwdLastSet
      whenCreated
      distinguishedName
    ].freeze

    def initialize
      @ldap = ActiveDirectoryAuthenticator.connection(
        username: ENV.fetch("HERGA_AD_SERVICE_USER"),
        password: ENV.fetch("HERGA_AD_SERVICE_PASSWORD")
      )

      @connected = false
    end

    # Read-only inventory of Active Directory computers.
    def computers(query: nil)
      filter = computer_filter

      term = query.to_s.strip.first(MAX_SEARCH_LENGTH)

      if term.present?
        escaped = Net::LDAP::Filter.escape(term)

        filter &= (
          Net::LDAP::Filter.eq("cn", "*#{escaped}*") |
          Net::LDAP::Filter.eq("sAMAccountName", "*#{escaped}*") |
          Net::LDAP::Filter.eq("dNSHostName", "*#{escaped}*") |
          Net::LDAP::Filter.eq("operatingSystem", "*#{escaped}*") |
          Net::LDAP::Filter.eq("description", "*#{escaped}*")
        )
      end

      entries = search(
        filter: filter,
        attributes: COMPUTER_ATTRIBUTES
      )

      entries
        .first(MAX_RESULTS)
        .map { |entry| build_computer(entry) }
        .sort_by { |computer| computer.name.downcase }
    end

    # Find one computer by its sAMAccountName.
    def find(account_name)
      name = account_name.to_s.strip

      return nil if name.blank?
      return nil if name.length > 256
      return nil if name.match?(/[[:cntrl:]]/)

      filter = computer_filter &
               Net::LDAP::Filter.eq(
                 "sAMAccountName",
                 Net::LDAP::Filter.escape(name)
               )

      entries = search(
        filter: filter,
        attributes: COMPUTER_ATTRIBUTES
      )

      return nil unless entries.length == 1

      build_computer(entries.first)
    end

    private

    def connect!
      return if @connected

      unless @ldap.bind
        raise DirectoryError,
              "Active Directory service account bind failed"
      end

      @connected = true
    end

    def search(filter:, attributes:)
      connect!

      entries = []

      result = @ldap.search(
        base: BASE_DN,
        filter: filter,
        attributes: attributes,
        return_result: false
      ) do |entry|
        entries << entry
      end

      operation = @ldap.get_operation_result

      unless operation.code == 0
        raise DirectoryError,
              "Active Directory search failed " \
              "(#{operation.code}): #{operation.message}"
      end

      raise DirectoryError, "Active Directory returned no search result" if result.nil?

      entries
    end

    def computer_filter
      Net::LDAP::Filter.eq("objectCategory", "computer") &
        Net::LDAP::Filter.eq("objectClass", "computer")
    end

    def attribute_value(entry, attribute)
      entry[attribute].first.to_s
    end

    def build_computer(entry)
      flags = attribute_value(entry, :useraccountcontrol).to_i

      Computer.new(
        name: attribute_value(entry, :cn),
        account_name: attribute_value(entry, :samaccountname),
        dns_hostname: attribute_value(entry, :dnshostname),
        description: attribute_value(entry, :description),
        operating_system: attribute_value(entry, :operatingsystem),
        operating_system_version: attribute_value(
          entry, :operatingsystemversion
        ),
        operating_system_service_pack: attribute_value(
          entry, :operatingsystemservicepack
        ),
        enabled: (flags & ACCOUNT_DISABLED).zero?,
        last_logon: windows_filetime(
          attribute_value(entry, :lastlogontimestamp)
        ),
        password_last_set: windows_filetime(
          attribute_value(entry, :pwdlastset)
        ),
        when_created: generalized_time(
          attribute_value(entry, :whencreated)
        ),
        dn: entry.dn.to_s
      )
    end

    def windows_filetime(value)
      ticks = value.to_i

      return nil if ticks <= WINDOWS_EPOCH_OFFSET

      seconds = (
        ticks - WINDOWS_EPOCH_OFFSET
      ).to_f / WINDOWS_TICKS_PER_SECOND

      Time.at(seconds).utc
    rescue RangeError, ArgumentError
      nil
    end

    def generalized_time(value)
      return nil if value.blank?

      Time.strptime(value, "%Y%m%d%H%M%S.%N%Z").utc
    rescue ArgumentError
      begin
        Time.strptime(value, "%Y%m%d%H%M%S%Z").utc
      rescue ArgumentError
        nil
      end
    end
  end
end
