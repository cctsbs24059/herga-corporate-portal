# frozen_string_literal: true

require "net/ldap"
require "openssl"

module ActiveDirectory
  class IncidentAssignmentEligibility
    REQUIRED_PERMISSION = :infrastructure_manage

    # --------------------------------------------------------
    # PUBLIC INTERFACE
    # --------------------------------------------------------

    # Return eligible local profiles using one LDAP connection.
    #
    # []  = no eligible candidates
    # nil = directory verification failed

    def self.candidates
      new.candidates
    end

    # Revalidate the selected candidate at submission time.

    def self.eligible?(user)
      new.eligible?(user)
    end

    # --------------------------------------------------------
    # CANDIDATE DISCOVERY
    # --------------------------------------------------------

    def candidates
      users = User.order(:username).to_a

      return [] if users.empty?

      with_directory do |ldap|
        eligible_users = []

        users.each do |user|
          eligibility = permitted?(ldap, user)

          # Never return a partially verified candidate list.
          return nil if eligibility.nil?

          eligible_users << user if eligibility
        end

        eligible_users
      end
    end

    # --------------------------------------------------------
    # INDIVIDUAL ASSIGNMENT VALIDATION
    # --------------------------------------------------------

    def eligible?(user)
      return false unless user

      with_directory do |ldap|
        permitted?(ldap, user)
      end == true
    end

    private

    # --------------------------------------------------------
    # RESILIENT DIRECTORY CONNECTION
    # --------------------------------------------------------

    def with_directory
      ActiveDirectoryAuthenticator.with_connection(
        username: ENV.fetch("HERGA_AD_SERVICE_USER"),
        password: ENV.fetch("HERGA_AD_SERVICE_PASSWORD")
      ) do |ldap|

        # Fail closed if no valid LDAP session is available.
        next nil if ldap.nil?

        yield ldap
      end

    rescue Net::LDAP::Error,
           OpenSSL::SSL::SSLError,
           IOError,
           SystemCallError,
           SocketError,
           Timeout::Error,
           KeyError => e

      Rails.logger.warn(
        "Incident assignment eligibility unavailable: #{e.class}"
      )

      nil
    end

    # --------------------------------------------------------
    # LIVE ACTIVE DIRECTORY PERMISSION VERIFICATION
    # --------------------------------------------------------

    def permitted?(ldap, user)
      return nil if ldap.nil?
      return false if user.nil?

      username = user.username.to_s

      return false unless username.match?(
        /\A[a-zA-Z0-9._-]+\z/
      )

      entry = ActiveDirectoryAuthenticator.find_user(
        ldap,
        username
      )

      unless entry
        result = ldap.get_operation_result

        return nil unless result && result.code == 0

        return false
      end

      roles = ActiveDirectory::RoleResolver.resolve(
        ldap: ldap,
        user_dn: entry.dn
      )

      # An unavailable or invalid role result must never
      # grant incident assignment eligibility.

      return nil unless roles.is_a?(Array)

      PortalAuthorization.allowed?(
        roles: roles,
        permission: REQUIRED_PERMISSION
      )
    end
  end
end