
# frozen_string_literal: true

require "net/ldap"
require "openssl"

module ActiveDirectory
  class GroupDirectory
    BASE_DN = ActiveDirectoryAuthenticator::BASE_DN

    MAX_RESULTS = 500
    MAX_SEARCH_LENGTH = 100
    MAX_MEMBERS = 200

    SECURITY_ENABLED = 0x80000000
    GLOBAL_GROUP = 0x00000002
    DOMAIN_LOCAL_GROUP = 0x00000004
    UNIVERSAL_GROUP = 0x00000008

    class DirectoryError < StandardError; end

    Group = Struct.new(
      :name,
      :account_name,
      :description,
      :email,
      :dn,
      :scope,
      :security,
      :members,
      :members_truncated,
      keyword_init: true
    )

    Member = Struct.new(
      :name,
      :account_name,
      :object_type,
      :dn,
      keyword_init: true
    )

    GROUP_ATTRIBUTES = %w[
      cn
      sAMAccountName
      description
      mail
      distinguishedName
      groupType
    ].freeze

    MEMBER_ATTRIBUTES = %w[
      cn
      displayName
      sAMAccountName
      objectClass
    ].freeze

    def initialize
      @ldap = ActiveDirectoryAuthenticator.connection(
        username: ENV.fetch("HERGA_AD_SERVICE_USER"),
        password: ENV.fetch("HERGA_AD_SERVICE_PASSWORD")
      )

      @connected = false
    end

    # List security groups, optionally filtered by name.
    def groups(query: nil)
      filter = security_group_filter

      term = query.to_s.strip.first(MAX_SEARCH_LENGTH)

      if term.present?
        escaped = Net::LDAP::Filter.escape(term)

        name_filter = Net::LDAP::Filter.eq(
          "cn", "*#{escaped}*"
        )

        account_filter = Net::LDAP::Filter.eq(
          "sAMAccountName", "*#{escaped}*"
        )

        description_filter = Net::LDAP::Filter.eq(
          "description", "*#{escaped}*"
        )

        filter &= (
          name_filter |
          account_filter |
          description_filter
        )
      end

      entries = search(
        base: BASE_DN,
        filter: filter,
        attributes: GROUP_ATTRIBUTES
      )

      entries
        .first(MAX_RESULTS)
        .map { |entry| build_group(entry) }
        .sort_by { |group| group.name.downcase }
    end

    # Find one security group using its account name.
    def find(account_name)
      name = account_name.to_s

      return nil if name.blank?
      return nil if name.length > 256
      return nil if name.match?(/[[:cntrl:]]/)

      filter = security_group_filter &
               Net::LDAP::Filter.eq(
                 "sAMAccountName",
                 Net::LDAP::Filter.escape(name)
               )

      entries = search(
        base: BASE_DN,
        filter: filter,
        attributes: GROUP_ATTRIBUTES + ["member"]
      )

      return nil unless entries.length == 1

      entry = entries.first
      group = build_group(entry)

      member_dns = entry[:member].map(&:to_s)

      group.members_truncated =
        member_dns.length > MAX_MEMBERS

      group.members = member_dns
        .first(MAX_MEMBERS)
        .map { |dn| build_member(dn) }
        .sort_by { |member| member.name.downcase }

      group
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

    def search(base:, filter:, attributes:, scope: nil)
      connect!

      options = {
        base: base,
        filter: filter,
        attributes: attributes,
        return_result: false
      }

      options[:scope] = scope if scope

      entries = []

      @ldap.search(**options) do |entry|
        entries << entry
      end

      operation = @ldap.get_operation_result

      unless operation.code == 0
        raise DirectoryError,
              "Active Directory search failed " \
              "(#{operation.code}): #{operation.message}"
      end

      entries
    end

    def security_group_filter
      Net::LDAP::Filter.eq(
        "objectCategory", "group"
      ) &
      Net::LDAP::Filter.construct(
        "(groupType:1.2.840.113556.1.4.803:=2147483648)"
      )
    end

    def attribute_value(entry, attribute)
      entry[attribute].first.to_s
    end

    def build_group(entry)
      flags = attribute_value(entry, :grouptype).to_i

      Group.new(
        name: attribute_value(entry, :cn),
        account_name: attribute_value(
          entry, :samaccountname
        ),
        description: attribute_value(
          entry, :description
        ),
        email: attribute_value(entry, :mail),
        dn: entry.dn.to_s,
        scope: group_scope(flags),
        security: (flags & SECURITY_ENABLED) != 0,
        members: [],
        members_truncated: false
      )
    end

    def group_scope(flags)
      if (flags & UNIVERSAL_GROUP) != 0
        "Universal"
      elsif (flags & DOMAIN_LOCAL_GROUP) != 0
        "Domain Local"
      elsif (flags & GLOBAL_GROUP) != 0
        "Global"
      else
        "Other"
      end
    end

    def build_member(dn)
      entries = search(
        base: dn,
        filter: Net::LDAP::Filter.present(
          "objectClass"
        ),
        attributes: MEMBER_ATTRIBUTES,
        scope: Net::LDAP::SearchScope_BaseObject
      )

      entry = entries.first

      unless entry
        return Member.new(
          name: dn,
          account_name: "",
          object_type: "Unknown",
          dn: dn
        )
      end

      classes = entry[:objectclass].map {
        |value| value.to_s.downcase
      }

      object_type =
        if classes.include?("computer")
          "Computer"
        elsif classes.include?("group")
          "Group"
        elsif classes.include?("user")
          "User"
        else
          "Other"
        end

      name = attribute_value(entry, :displayname)
      name = attribute_value(entry, :cn) if name.blank?
      name = dn if name.blank?

      Member.new(
        name: name,
        account_name: attribute_value(
          entry, :samaccountname
        ),
        object_type: object_type,
        dn: dn
      )
    end
  end
end
