
# Authenticates HERGA employees against Active Directory.
#
# Security:
# - Requires an encrypted LDAPS connection.
# - Validates the domain controller's TLS certificate.
# - Never stores the employee's password.
# - Requires membership in an approved AD group.
# - Fails closed if LDAP searches fail.

require "net/ldap"
require "openssl"

class ActiveDirectoryAuthenticator
  DOMAIN = "HERGA"
  DNS_DOMAIN = "herga.net"
  SERVER = "csi.herga.net"
  BASE_DN = "DC=herga,DC=net"

  USER_GROUP = "HERGA-Portal-Users"
  ADMIN_GROUP = "HERGA-Portal-Admins"

  # AD matching rule for recursive group membership.
  CHAIN_RULE = "1.2.840.113556.1.4.1941"

  Result = Struct.new(
    :username,
    :email,
    :display_name,
    :dn,
    :admin,
    keyword_init: true
  )

  # Accept Windows-style usernames such as HERGA\bkava.
  def self.parse_username(value)
    match = /\A#{DOMAIN}\\([a-zA-Z0-9._-]+)\z/i.match(
      value.to_s.strip
    )

    match && match[1].downcase
  end


# Establish an LDAPS connection to HERGA.NET.
#
# LAB ENVIRONMENT ONLY:
# SSL certificate verification is disabled.
#
# The connection remains encrypted using TLS,
# but the domain controller's identity is not verified.
#
# Do not use this configuration in a production
# environment containing real corporate credentials.

  def self.connection(username:, password:)
    Net::LDAP.new(
        host: "csi.herga.net",
        port: 636,

        # Establish an encrypted LDAPS connection.
        encryption: {
            method: :simple_tls,
            tls_options: {
                # Disable verification only when explicitly configured
                # in a non-production environment.
                verify_mode: (
                !Rails.env.production? &&
                ENV["HERGA_LDAP_SKIP_CERT_VERIFY"] == "true"
                ) ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
            }
        },

        # Authenticate using Active Directory credentials.
        auth: {
        method: :simple,
        username: username,
        password: password
        }
    )
  end

  # Validate credentials and authorisation.
  #
  # Returns a Result on success or nil on failure.
  def self.authenticate(login, password)
    username = parse_username(login)

    return nil if username.nil?
    return nil if password.to_s.empty?

    # Use the employee's own credentials for the bind.
    # No separate LDAP service-account password is needed.
    ldap = connection(
      username: "#{username}@#{DNS_DOMAIN}",
      password: password
    )

    return nil unless ldap.bind

    # Search for exactly one matching AD user.
    user_filter = Net::LDAP::Filter.eq(
      "sAMAccountName", username
    ) & Net::LDAP::Filter.eq(
      "objectCategory", "person"
    )

    entries = ldap.search(
      base: BASE_DN,
      filter: user_filter,
      attributes: [
        "distinguishedName",
        "sAMAccountName",
        "mail",
        "displayName"
      ],
      size: 2
    )

    # Reject missing, ambiguous or failed searches.
    return nil unless ldap.get_operation_result.code == 0
    return nil unless entries&.length == 1

    entry = entries.first
    user_dn = entry.dn

    # Locate both portal security groups.
    user_group_dn = group_dn(ldap, USER_GROUP)
    admin_group_dn = group_dn(ldap, ADMIN_GROUP)

    return nil unless user_group_dn && admin_group_dn

    # Administrators may enter through their admin group.
    # Ordinary employees need the employee group.
    is_admin = member_of?(ldap, user_dn, admin_group_dn)
    is_user = member_of?(ldap, user_dn, user_group_dn)

    return nil if is_admin.nil? || is_user.nil?
    return nil unless is_admin || is_user

    Result.new(
      username: username,
      email: entry.mail.first.to_s.presence,
      display_name: entry.displayname.first.to_s.presence ||
                    username,
      dn: user_dn,
      admin: is_admin
    )
  rescue Net::LDAP::Error, OpenSSL::SSL::SSLError,
         IOError, SystemCallError, Timeout::Error => e
    # Log the error class, never passwords or credentials.
    Rails.logger.warn(
      "AD authentication unavailable: #{e.class}"
    )

    nil
  end

  # Resolve an AD group using its sAMAccountName.
  def self.group_dn(ldap, group_name)
    filter = Net::LDAP::Filter.eq(
      "sAMAccountName", group_name
    ) & Net::LDAP::Filter.eq(
      "objectCategory", "group"
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

  # Check direct or nested AD security-group membership.
  #
  # Search the user's DN with the Microsoft matching rule.
  # This avoids relying on a potentially truncated memberOf
  # attribute returned during the initial user lookup.
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


  # Return the user's current AD permissions.
  #
  # This method uses the read-only service account rather
  # than the employee's password, which is not retained.
  #
  # Returns:
  #   :admin    - administrator access
  #   :employee - ordinary portal access
  #   nil       - denied or directory unavailable
  def self.current_role(username)
    return nil unless username.to_s.match?(/\A[a-zA-Z0-9._-]+\z/)

    service_user = ENV.fetch("HERGA_AD_SERVICE_USER")
    service_password = ENV.fetch("HERGA_AD_SERVICE_PASSWORD")

    ldap = connection(
      username: service_user,
      password: service_password
    )

    return nil unless ldap.bind

    user_filter = Net::LDAP::Filter.eq(
      "sAMAccountName", username
    ) & Net::LDAP::Filter.eq(
      "objectCategory", "person"
    )

    entries = ldap.search(
      base: BASE_DN,
      filter: user_filter,
      attributes: ["distinguishedName"],
      size: 2
    )

    return nil unless ldap.get_operation_result.code == 0
    return nil unless entries&.length == 1

    user_dn = entries.first.dn

    admin_dn = group_dn(ldap, ADMIN_GROUP)
    employee_dn = group_dn(ldap, USER_GROUP)

    return nil unless admin_dn && employee_dn

    admin = member_of?(ldap, user_dn, admin_dn)
    employee = member_of?(ldap, user_dn, employee_dn)

    # Fail closed if either membership check fails.
    return nil if admin.nil? || employee.nil?

    return :admin if admin
    return :employee if employee

    nil
  rescue Net::LDAP::Error, OpenSSL::SSL::SSLError,
         IOError, SystemCallError, Timeout::Error,
         KeyError => e
    Rails.logger.warn(
      "AD authorisation unavailable: #{e.class}"
    )

    nil
  end


end
