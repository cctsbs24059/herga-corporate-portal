
# frozen_string_literal: true

# HERGA Corporate Portal
# Phase 2E.1c - Active Directory Authentication and RBAC
#
# Security:
# - LDAPS with TLS certificate validation in production.
# - Authentication uses the employee's own AD credentials.
# - Per-request authorisation uses the read-only service account.
# - Direct and nested AD group membership is supported.
# - Multiple application roles are supported.
# - Missing groups and failed LDAP queries deny access.
# - Passwords are never stored in the Rails database.

require "net/ldap"
require "openssl"

class ActiveDirectoryAuthenticator
  DOMAIN = "HERGA"
  DNS_DOMAIN = "herga.net"
  SERVER = "csi.herga.net"
  BASE_DN = "DC=herga,DC=net"

  USER_GROUP = "HERGA-Portal-Users"
  ADMIN_GROUP = "HERGA-Portal-Admins"

  CHAIN_RULE = "1.2.840.113556.1.4.1941"

  Result = Struct.new(
    :username,
    :email,
    :display_name,
    :dn,
    :admin,
    :roles,
    keyword_init: true
  )

  # Accept Windows-style usernames, e.g. HERGA\bkava.
  def self.parse_username(value)
    match = /\A#{DOMAIN}\\([a-zA-Z0-9._-]+)\z/i.match(
      value.to_s.strip
    )

    match && match[1].downcase
  end

  # Establish an encrypted LDAPS connection.
  #
  # Certificate verification can only be disabled when
  # explicitly configured outside production.
  def self.connection(username:, password:)
    skip_verification =
      !Rails.env.production? &&
      ENV["HERGA_LDAP_SKIP_CERT_VERIFY"] == "true"

    Net::LDAP.new(
      host: SERVER,
      port: 636,
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

  # Authenticate an employee using their AD credentials.
  #
  # Returns Result on success, nil on failure.
  def self.authenticate(login, password)
    username = parse_username(login)

    return nil if username.nil?
    return nil if password.to_s.empty?

    ldap = connection(
      username: "#{username}@#{DNS_DOMAIN}",
      password: password
    )

    return nil unless ldap.bind

    entry = find_user(ldap, username)
    return nil unless entry

    roles = ActiveDirectory::RoleResolver.resolve(
      ldap: ldap,
      user_dn: entry.dn
    )

    # nil means directory failure.
    # [] means no approved group membership.
    return nil if roles.nil? || roles.empty?

    Result.new(
      username: username,
      email: entry.mail.first.to_s.presence,
      display_name: entry.displayname.first.to_s.presence ||
                    username,
      dn: entry.dn,
      admin: roles.include?(:portal_admin),
      roles: roles
    )
  rescue Net::LDAP::Error,
         OpenSSL::SSL::SSLError,
         IOError,
         SystemCallError,
         Timeout::Error,
         KeyError => e

    Rails.logger.warn(
      "AD authentication unavailable: #{e.class}"
    )

    nil
  end

  # Resolve the user's current application roles.
  #
  # This is called on authenticated requests using the
  # configured read-only AD lookup service account.
  #
  # Returns:
  #   Array<Symbol> - verified roles
  #   []            - no authorised memberships
  #   nil           - directory failure
  def self.current_roles(username)
    return nil unless username.to_s.match?(
      /\A[a-zA-Z0-9._-]+\z/
    )

    service_user = ENV.fetch("HERGA_AD_SERVICE_USER")
    service_password = ENV.fetch("HERGA_AD_SERVICE_PASSWORD")

    ldap = connection(
      username: service_user,
      password: service_password
    )

    return nil unless ldap.bind

    entry = find_user(ldap, username)
    return nil unless entry

    ActiveDirectory::RoleResolver.resolve(
      ldap: ldap,
      user_dn: entry.dn
    )
  rescue Net::LDAP::Error,
         OpenSSL::SSL::SSLError,
         IOError,
         SystemCallError,
         Timeout::Error,
         KeyError => e

    Rails.logger.warn(
      "AD authorisation unavailable: #{e.class}"
    )

    nil
  end

  # Backward-compatible legacy role method.
  #
  # Existing code that calls current_role continues
  # to receive :admin, :employee or nil.
  #
  # New RBAC code should use current_roles instead.
  def self.current_role(username)
    roles = current_roles(username)

    return nil if roles.nil? || roles.empty?

    return :admin if roles.include?(:portal_admin)

    :employee
  end

  # Find exactly one AD user.
  def self.find_user(ldap, username)
    filter = Net::LDAP::Filter.eq(
      "sAMAccountName",
      username
    ) & Net::LDAP::Filter.eq(
      "objectCategory",
      "person"
    )

    entries = ldap.search(
      base: BASE_DN,
      filter: filter,
      attributes: [
        "distinguishedName",
        "sAMAccountName",
        "mail",
        "displayName"
      ],
      size: 2
    )

    return nil unless ldap.get_operation_result.code == 0
    return nil unless entries&.length == 1

    entries.first
  end

  # Find an AD security group by sAMAccountName.
  #
  # Reused by ActiveDirectory::RoleResolver.
  def self.group_dn(ldap, group_name)
    filter = Net::LDAP::Filter.eq(
      "sAMAccountName",
      group_name
    ) & Net::LDAP::Filter.eq(
      "objectCategory",
      "group"
    )

    entries = ldap.search(
      base: BASE_DN,
      filter: filter,
      attributes: ["distinguishedName"],
      size: 2
    )

    return nil unless ldap.get_operation_result.code == 0
    return nil unless entries&.length == 1

    entries.first.dn
  end

  # Check direct or nested AD group membership.
  #
  # Microsoft LDAP matching rule:
  # 1.2.840.113556.1.4.1941
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

    return nil unless ldap.get_operation_result.code == 0

    entries&.any? || false
  end
end
