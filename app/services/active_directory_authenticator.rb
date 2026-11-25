# frozen_string_literal: true

require "net/ldap"
require "openssl"

class ActiveDirectoryAuthenticator

  # ==========================================================
  # ACTIVE DIRECTORY CONFIGURATION
  # ==========================================================

  DOMAIN = ENV.fetch(
    "HERGA_AD_DOMAIN", "HERGA"
  ).strip.freeze

  DNS_DOMAIN = ENV.fetch(
    "HERGA_AD_DNS_DOMAIN", "herga.net"
  ).strip.freeze

  BASE_DN = ENV.fetch(
    "HERGA_AD_BASE_DN", "DC=herga,DC=net"
  ).strip.freeze

  LDAP_SERVERS = ENV.fetch(
    "HERGA_AD_SERVERS", "csi.herga.net"
  ).split(",")
   .map(&:strip)
   .reject(&:empty?)
   .uniq
   .map(&:freeze)
   .freeze

  LDAP_PORT = Integer(
    ENV.fetch("HERGA_AD_PORT", "636"), 10
  )

  LDAP_CONNECT_TIMEOUT = Integer(
    ENV.fetch("HERGA_AD_CONNECT_TIMEOUT", "3"), 10
  )

  # ==========================================================
  # CONFIGURATION VALIDATION
  # ==========================================================

  if LDAP_SERVERS.empty?
    raise ArgumentError,
          "HERGA_AD_SERVERS must contain at least one server"
  end

  unless LDAP_PORT.between?(1, 65_535)
    raise ArgumentError,
          "HERGA_AD_PORT must be between 1 and 65535"
  end

  unless LDAP_CONNECT_TIMEOUT.positive?
    raise ArgumentError,
          "HERGA_AD_CONNECT_TIMEOUT must be positive"
  end

  # Legacy compatibility.
  SERVER = LDAP_SERVERS.first

  USER_GROUP = "HERGA-Portal-Users"
  ADMIN_GROUP = "HERGA-Portal-Admins"

  # Active Directory recursive membership matching rule.
  CHAIN_RULE = "1.2.840.113556.1.4.1941"

  ACCOUNT_DISABLED_FLAG = 0x0002
  SECURITY_ENABLED_FLAG = 0x80000000

  Result = Struct.new(
    :username,
    :email,
    :display_name,
    :dn,
    :admin,
    :roles,
    keyword_init: true
  )

  # ==========================================================
  # USERNAME VALIDATION
  # ==========================================================

  def self.parse_username(value)
    match = /\A#{Regexp.escape(DOMAIN)}\\([a-zA-Z0-9._-]+)\z/i.match(
      value.to_s.strip
    )

    match && match[1].downcase
  end

  # ==========================================================
  # LDAP SERVER CONFIGURATION
  # ==========================================================

  def self.ldap_hosts
    LDAP_SERVERS.map do |server|
      [server, LDAP_PORT]
    end
  end

  # ==========================================================
  # LDAP CONNECTION FACTORY
  # ==========================================================

  def self.connection(username:, password:)
    skip_verification =
      !Rails.env.production? &&
      ENV["HERGA_LDAP_SKIP_CERT_VERIFY"] == "true"

    Net::LDAP.new(
      hosts: ldap_hosts,

      connect_timeout: LDAP_CONNECT_TIMEOUT,

      encryption: {
        method: :simple_tls,

        tls_options: {
          verify_mode: skip_verification ?
            OpenSSL::SSL::VERIFY_NONE :
            OpenSSL::SSL::VERIFY_PEER
        }
      },

      auth: {
        method: :simple,
        username: username,
        password: password
      }
    )
  end

  # ==========================================================
  # CENTRALISED LDAP CONNECTION LIFECYCLE
  #
  # Establishes one connection for the entire operation.
  # Native Net LDAP connection failover remains enabled.
  # The initial bind must succeed before queries are permitted.
  # The connection is automatically closed by Net LDAP.
  # ==========================================================

  def self.with_connection(username:, password:)
    return nil if username.to_s.strip.empty?
    return nil if password.to_s.empty?

    ldap = connection(
      username: username,
      password: password
    )

    ldap.open do |session|
      result = session.get_operation_result

      unless result && result.code == 0
        Rails.logger.warn(
          "AD connection rejected: LDAP bind unsuccessful"
        )

        return nil
      end

      return yield session
    end

    nil
  end

  # ==========================================================
  # USER AUTHENTICATION
  # ==========================================================

  def self.authenticate(login, password)
    username = parse_username(login)

    return nil if username.nil?
    return nil if password.to_s.empty?

    with_connection(
      username: "#{username}@#{DNS_DOMAIN}",
      password: password
    ) do |ldap|

      entry = find_user(ldap, username)

      next nil unless entry && account_enabled?(entry) == true

      roles = ActiveDirectory::RoleResolver.resolve(
        ldap: ldap,
        user_dn: entry.dn
      )

      next nil if roles.nil? || roles.empty?

      Result.new(
        username: username,
        email: optional_attribute(entry, :mail),

        display_name:
          optional_attribute(entry, :displayname) || username,

        dn: entry.dn,

        admin: roles.include?(:portal_admin),

        roles: roles
      )
    end

  rescue Net::LDAP::Error,
         OpenSSL::SSL::SSLError,
         IOError,
         SystemCallError,
         SocketError,
         Timeout::Error,
         KeyError => e

    Rails.logger.warn(
      "AD authentication unavailable: #{e.class}"
    )

    nil
  end

  # ==========================================================
  # LIVE ACTIVE DIRECTORY ROLE RESOLUTION
  # ==========================================================

  def self.current_roles(username)
    return nil unless username.to_s.match?(
      /\A[a-zA-Z0-9._-]+\z/
    )

    service_user = ENV.fetch(
      "HERGA_AD_SERVICE_USER"
    )

    service_password = ENV.fetch(
      "HERGA_AD_SERVICE_PASSWORD"
    )

    with_connection(
      username: service_user,
      password: service_password
    ) do |ldap|

      entry = find_user(ldap, username)

      next nil unless entry && account_enabled?(entry) == true

      ActiveDirectory::RoleResolver.resolve(
        ldap: ldap,
        user_dn: entry.dn
      )
    end

  rescue Net::LDAP::Error,
         OpenSSL::SSL::SSLError,
         IOError,
         SystemCallError,
         SocketError,
         Timeout::Error,
         KeyError => e

    Rails.logger.warn(
      "AD authorisation unavailable: #{e.class}"
    )

    nil
  end

  # ==========================================================
  # LEGACY ROLE COMPATIBILITY
  # ==========================================================

  def self.current_role(username)
    roles = current_roles(username)

    return nil if roles.nil? || roles.empty?

    return :admin if roles.include?(:portal_admin)

    :employee
  end

  # ==========================================================
  # ACTIVE DIRECTORY USER LOOKUP
  # ==========================================================

  # Mandatory attributes must contain exactly one valid decimal integer.
  def self.integer_attribute(entry, attribute)
    values = entry[attribute]
    return nil unless values.is_a?(Array) && values.length == 1

    value = values.first.to_s
    return nil unless value.match?(/\A-?[0-9]+\z/)

    Integer(value, 10)
  rescue ArgumentError, KeyError, IndexError
    nil
  end

  def self.optional_attribute(entry, attribute)
    Array(entry[attribute]).first.to_s.presence
  rescue KeyError, IndexError
    nil
  end

  # true = enabled; false = disabled; nil = unverifiable.
  def self.account_enabled?(entry)
    value = integer_attribute(entry, :useraccountcontrol)
    return nil unless value && value.between?(1, 0xFFFFFFFF)

    (value & ACCOUNT_DISABLED_FLAG).zero?
  end

  def self.security_group?(entry)
    value = integer_attribute(entry, :grouptype)
    return false unless value && value.between?(-0x80000000, 0xFFFFFFFF)

    (value & SECURITY_ENABLED_FLAG) != 0
  end

  def self.find_user(ldap, username)
    filter =
      Net::LDAP::Filter.eq(
        "sAMAccountName", username
      ) &
      Net::LDAP::Filter.eq(
        "objectCategory", "person"
      )

    entries = ldap.search(
      base: BASE_DN,
      filter: filter,

      attributes: [
        "distinguishedName",
        "sAMAccountName",
        "mail",
        "displayName",
        "userAccountControl"
      ],

      size: 2
    )

    return nil unless ldap.get_operation_result&.code == 0

    return nil unless entries&.length == 1

    entries.first
  end

  # ==========================================================
  # ACTIVE DIRECTORY GROUP LOOKUP
  # ==========================================================

  def self.group_dn(ldap, group_name)
    filter =
      Net::LDAP::Filter.eq(
        "sAMAccountName", group_name
      ) &
      Net::LDAP::Filter.eq(
        "objectCategory", "group"
      )

    entries = ldap.search(
      base: BASE_DN,
      filter: filter,
      attributes: ["distinguishedName", "groupType"],
      size: 2
    )

    return nil unless ldap.get_operation_result&.code == 0

    return nil unless entries&.length == 1

    entry = entries.first
    return nil unless security_group?(entry)

    entry.dn
  end

  # ==========================================================
  # RECURSIVE ACTIVE DIRECTORY GROUP MEMBERSHIP
  # ==========================================================

  def self.member_of?(ldap, user_dn, group_dn)
    escaped_dn = Net::LDAP::Filter.escape(group_dn)

    filter = Net::LDAP::Filter.construct(
      "(memberOf:#{CHAIN_RULE}:=#{escaped_dn})"
    )

    entries = ldap.search(
      base: user_dn,
      scope: Net::LDAP::SearchScope_BaseObject,
      filter: filter,
      attributes: ["distinguishedName"],
      size: 1
    )

    return nil unless ldap.get_operation_result&.code == 0

    return nil unless entries.is_a?(Array)

    entries.any?
  end
end
