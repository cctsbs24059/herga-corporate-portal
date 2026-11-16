
# frozen_string_literal: true

# ============================================================
# HERGA CORPORATE PORTAL
# Active Directory User Directory Service
# ============================================================
#
# Purpose:
#   Retrieve Active Directory user information for the
#   HERGA Corporate Portal.
#
# Features:
#   - Read-only Active Directory access
#   - Reuses existing LDAPS connection configuration
#   - Searches users by name, username and email
#   - Retrieves account information
#   - Identifies enabled and disabled accounts
#   - Retrieves direct security group memberships
#   - Handles missing LDAP attributes safely
#   - Fails closed when directory queries fail
#
# Security:
#   - Uses HERGA_AD_SERVICE_USER
#   - Uses HERGA_AD_SERVICE_PASSWORD
#   - Never modifies Active Directory objects
#   - Never logs service account credentials
#   - Uses escaped LDAP search filters
#
# ============================================================

require "net/ldap"
require "openssl"

module ActiveDirectory

  class UserDirectory

    # --------------------------------------------------------
    # ACTIVE DIRECTORY CONFIGURATION
    # --------------------------------------------------------

    # Reuse the existing authentication service configuration.
    BASE_DN = ActiveDirectoryAuthenticator::BASE_DN

    # Maximum number of entries returned by a query.

    MAX_RESULTS = 500
    LDAP_PAGE_SIZE = 100

    # Maximum permitted search string length.
    MAX_SEARCH_LENGTH = 100

    # --------------------------------------------------------
    # USER DATA STRUCTURE
    # --------------------------------------------------------

    User = Struct.new(
      :username,
      :display_name,
      :email,
      :department,
      :job_title,
      :enabled,
      :dn,
      :groups,
      keyword_init: true
    )

    # Custom error raised when directory operations fail.
    class DirectoryError < StandardError; end

    # --------------------------------------------------------
    # ACTIVE DIRECTORY ATTRIBUTES
    # --------------------------------------------------------

    ATTRIBUTES = %w[
      sAMAccountName
      displayName
      mail
      department
      title
      userAccountControl
      distinguishedName
    ].freeze

    # --------------------------------------------------------
    # INITIALISE LDAP CONNECTION
    # --------------------------------------------------------

    def initialize

      # Retrieve service account credentials.
      service_user = ENV.fetch(
        "HERGA_AD_SERVICE_USER"
      )

      service_password = ENV.fetch(
        "HERGA_AD_SERVICE_PASSWORD"
      )

      # Reuse the existing LDAPS connection implementation.
      #
      # Certificate verification remains controlled by
      # ActiveDirectoryAuthenticator.connection.

      @ldap = ActiveDirectoryAuthenticator.connection(
        username: service_user,
        password: service_password
      )

      @connected = false

    end

    # --------------------------------------------------------
    # LIST ACTIVE DIRECTORY USERS
    # --------------------------------------------------------

    # Returns a bounded list of Active Directory users.
    #
    # Optional query searches:
    #   - Display name
    #   - Username
    #   - Email address
    #
    # This initial implementation retrieves up to
    # MAX_RESULTS matching users.

    def users(query: nil)

      # Restrict results to Active Directory user objects.
      search_filter =
        Net::LDAP::Filter.eq(
          "objectCategory", "person"
        ) &
        Net::LDAP::Filter.eq(
          "objectClass", "user"
        )

      # Apply optional search criteria.
      if query.present?

        term = query.to_s.strip.first(
          MAX_SEARCH_LENGTH
        )

        if term.present?

          escaped_term = escape(term)

          display_name_filter =
            Net::LDAP::Filter.eq(
              "displayName",
              "*#{escaped_term}*"
            )

          username_filter =
            Net::LDAP::Filter.eq(
              "sAMAccountName",
              "*#{escaped_term}*"
            )

          email_filter =
            Net::LDAP::Filter.eq(
              "mail",
              "*#{escaped_term}*"
            )

          name_filter =
            display_name_filter |
            username_filter |
            email_filter

          search_filter &= name_filter

        end

      end

      # Execute the LDAP query.
      entries = search(
        filter: search_filter,
        attributes: ATTRIBUTES,
        size: MAX_RESULTS
      )

      # Convert LDAP entries into structured user records.
      users = entries.map do |entry|
        build_user(entry)
      end

      # Sort results by display name.
      users.sort_by do |user|
        user.display_name.downcase
      end

    end

    # --------------------------------------------------------
    # FIND AN INDIVIDUAL USER
    # --------------------------------------------------------

    # Retrieves one AD user using sAMAccountName.
    #
    # Returns:
    #   User object when found
    #   nil when no matching account exists
    #
    # Raises DirectoryError if LDAP fails.

    def find(username)

      # Validate the supplied username.
      unless username.to_s.match?(
        /\A[a-zA-Z0-9._-]+\z/
      )
        return nil
      end

      # Construct an exact-match LDAP filter.
      filter =
        Net::LDAP::Filter.eq(
          "sAMAccountName",
          username
        ) &
        Net::LDAP::Filter.eq(
          "objectCategory",
          "person"
        ) &
        Net::LDAP::Filter.eq(
          "objectClass",
          "user"
        )

      # Retrieve a maximum of two entries.
      # Two results would indicate an ambiguous lookup.
      entries = search(
        filter: filter,
        attributes: ATTRIBUTES,
        size: 2
      )

      return nil unless entries.length == 1

      entry = entries.first

      # Convert the LDAP entry into a User object.
      user = build_user(entry)

      # Retrieve direct security group memberships.
      user.groups = groups_for(entry.dn)

      user

    end

    # --------------------------------------------------------
    # PRIVATE METHODS
    # --------------------------------------------------------

    private

    # --------------------------------------------------------
    # ESCAPE LDAP FILTER VALUES
    # --------------------------------------------------------

    def escape(value)

      Net::LDAP::Filter.escape(
        value.to_s
      )

    end

    # --------------------------------------------------------
    # ESTABLISH LDAP CONNECTION
    # --------------------------------------------------------

    def connect!

      return if @connected

      # Bind using the configured read-only account.
      unless @ldap.bind

        raise DirectoryError,
              "Active Directory bind failed"

      end

      @connected = true

    end

    # --------------------------------------------------------
    # EXECUTE LDAP SEARCH
    # --------------------------------------------------------


    def search(filter:, attributes:, size:)
      connect!

      entries = []

      # net-ldap 0.21.0 supports automatic paged searches
      # through its search implementation.
      #
      # Do not set paged_searches_supported.
      # Do not pass size:, which can trigger LDAP error 4.

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

      # Apply the application display limit after retrieval.
      entries.first(size)
    end


    # --------------------------------------------------------
    # SAFE LDAP ATTRIBUTE ACCESS
    # --------------------------------------------------------

    # Some Active Directory accounts do not contain every
    # optional attribute.
    #
    # Using entry[:attribute] avoids NoMethodError when an
    # attribute is absent.
    #
    # Returns an empty string when the value is unavailable.

    def attribute_value(entry, attribute)

      entry[attribute].first.to_s

    end

    # --------------------------------------------------------
    # BUILD USER OBJECT
    # --------------------------------------------------------

    def build_user(entry)

      # Retrieve account identity.
      username = attribute_value(
        entry,
        :samaccountname
      )

      display_name = attribute_value(
        entry,
        :displayname
      )

      # Retrieve optional attributes safely.
      email = attribute_value(
        entry,
        :mail
      )

      department = attribute_value(
        entry,
        :department
      )

      job_title = attribute_value(
        entry,
        :title
      )

      # ------------------------------------------------------
      # ACCOUNT STATUS
      # ------------------------------------------------------

      # userAccountControl is an AD bitmask.
      #
      # ACCOUNTDISABLE = 0x0002
      #
      # If the attribute is absent, the account status
      # must not automatically be considered enabled.

      raw_flags = entry[:useraccountcontrol].first

      enabled =
        if raw_flags.nil?
          nil
        else
          flags = raw_flags.to_i
          (flags & 2).zero?
        end

      # ------------------------------------------------------
      # CREATE USER RECORD
      # ------------------------------------------------------

      User.new(
        username: username,

        display_name: display_name.presence ||
                      username,

        email: email,

        department: department,

        job_title: job_title,

        enabled: enabled,

        dn: entry.dn,

        groups: []
      )

    end

    # --------------------------------------------------------
    # RETRIEVE DIRECT SECURITY GROUP MEMBERSHIPS
    # --------------------------------------------------------

    # Finds groups whose member attribute directly
    # references the selected user's distinguished name.
    #
    # Nested group membership is not included.
    #
    # Results are limited to MAX_RESULTS.

    def groups_for(user_dn)

      filter =
        Net::LDAP::Filter.eq(
          "objectCategory",
          "group"
        ) &
        Net::LDAP::Filter.eq(
          "member",
          user_dn
        )

      entries = search(
        filter: filter,
        attributes: %w[cn],
        size: MAX_RESULTS
      )

      # Safely retrieve group names.
      groups = entries.map do |entry|
        attribute_value(entry, :cn)
      end

      # Remove empty values, duplicates and sort.
      groups.reject(&:blank?)
            .uniq
            .sort

    end

  end

end
