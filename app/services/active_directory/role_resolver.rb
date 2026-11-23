
# frozen_string_literal: true

# HERGA Corporate Portal
# Phase 2E.1b - Active Directory Role Resolution
#
# Resolves direct and nested Active Directory group membership
# into application RBAC roles.
#
# This service reuses ActiveDirectoryAuthenticator.group_dn
# and ActiveDirectoryAuthenticator.member_of?.
#
# Return values:
#   Array<Symbol> - successfully resolved roles
#   []            - valid lookup, no recognised memberships
#   nil           - directory lookup or configuration failure
#
# A missing configured group is treated as an error.
# No permissions are granted on directory failure.

require "net/ldap"
require "openssl"

module ActiveDirectory
  class RoleResolver
    GROUP_ROLES = {
      "HERGA-Portal-Admins" => :portal_admin,
      "HERGA-Portal-Infrastructure-Admins" => :infrastructure_admin,
      "HERGA-Portal-Security-Admins" => :security_admin,
      "HERGA-Portal-Auditors" => :auditor,
      "HERGA-Portal-Users" => :employee
    }.freeze

    def self.resolve(ldap:, user_dn:)
      new(ldap: ldap, user_dn: user_dn).resolve
    end

    def initialize(ldap:, user_dn:)
      @ldap = ldap
      @user_dn = user_dn
    end

    def resolve
      return nil if @ldap.nil?
      return nil if @user_dn.to_s.strip.empty?

      # Resolve every configured security group first.
      # This prevents partial role assignments when the
      # directory configuration is incomplete.
      group_dns = {}

      GROUP_ROLES.each_key do |group_name|
        dn = ActiveDirectoryAuthenticator.group_dn(
          @ldap,
          group_name
        )

        if dn.to_s.empty?
          Rails.logger.warn(
            "HERGA RBAC group resolution failed: #{group_name}"
          )
          return nil
        end

        group_dns[group_name] = dn
      end

      roles = []

      GROUP_ROLES.each do |group_name, role|
        membership = ActiveDirectoryAuthenticator.member_of?(
          @ldap,
          @user_dn,
          group_dns.fetch(group_name)
        )

        # Never grant a partial role set when any
        # membership lookup has failed.
        return nil if membership.nil?

        roles << role if membership == true
      end

      roles.freeze
    rescue Net::LDAP::Error,
           OpenSSL::SSL::SSLError,
           IOError,
           SystemCallError,
           Timeout::Error => e
      Rails.logger.warn(
        "HERGA RBAC role resolution unavailable: #{e.class}"
      )

      nil
    end
  end
end
