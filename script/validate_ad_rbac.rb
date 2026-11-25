
# frozen_string_literal: true

# ============================================================
# HERGA CORPORATE PORTAL
# LIVE ACTIVE DIRECTORY RBAC VALIDATION
#
# Validates:
# - Live Active Directory role resolution
# - Individual specialist roles
# - Multiple-role permission aggregation
# - Least privilege
# - Unauthorised user permission denial
#
# This script is read-only.
# It does not modify Active Directory or the application database.
# ============================================================

ad = ActiveDirectoryAuthenticator
authorization = PortalAuthorization

# ============================================================
# INDEPENDENT EXPECTED PERMISSION MATRIX
# ============================================================

permissions = %i[
  portal_read
  infrastructure_read
  infrastructure_manage
  governance_read
  governance_manage
  governance_evidence_read
  portal_applications_manage
].freeze

accounts = {

  "hu500" => {
    description: "Portal Administrator",
    roles: [:portal_admin],
    permissions: %i[
      portal_read
      infrastructure_read
      infrastructure_manage
      governance_read
      governance_manage
      governance_evidence_read
      portal_applications_manage
    ]
  },

  "hu100" => {
    description: "Employee",
    roles: [:employee],
    permissions: %i[
      portal_read
    ]
  },

  "herga-test-infra" => {
    description: "Infrastructure Administrator",
    roles: [:infrastructure_admin],
    permissions: %i[
      portal_read
      infrastructure_read
      infrastructure_manage
    ]
  },

  "herga-test-security" => {
    description: "Security Administrator",
    roles: [:security_admin],
    permissions: %i[
      portal_read
      infrastructure_read
      governance_read
      governance_manage
      governance_evidence_read
    ]
  },

  "herga-test-auditor" => {
    description: "Auditor",
    roles: [:auditor],
    permissions: %i[
      portal_read
      infrastructure_read
      governance_read
      governance_evidence_read
    ]
  },

  "herga-test-multi" => {
    description: "Infrastructure Administrator + Auditor",
    roles: %i[
      infrastructure_admin
      auditor
    ],
    permissions: %i[
      portal_read
      infrastructure_read
      infrastructure_manage
      governance_read
      governance_evidence_read
    ]
  },

  "herga-test-denied" => {
    description: "Unauthorised Domain User",
    roles: [],
    permissions: []
  }

}.freeze

# ============================================================
# OUTPUT FORMATTING
# ============================================================

def coloured_status(passed)
  if passed
    "\e[32m[PASS]\e[0m"
  else
    "\e[31m[FAIL]\e[0m"
  end
end

def permission_label(granted)
  granted ? "GRANTED" : "DENIED"
end

# ============================================================
# VALIDATION COUNTERS
# ============================================================

role_passed = 0
role_failed = 0

permission_passed = 0
permission_failed = 0

durations = []

# ============================================================
# VALIDATION HEADER
# ============================================================

puts "=" * 85
puts "HERGA CORPORATE PORTAL"
puts "LIVE ACTIVE DIRECTORY RBAC VALIDATION"
puts "=" * 85

puts "Timestamp:          #{Time.current}"
puts "Rails environment:  #{Rails.env}"
puts "Ruby version:       #{RUBY_VERSION}"
puts "Accounts:           #{accounts.size}"
puts "Permissions:        #{permissions.size}"

puts
puts "Configured authentication servers:"

ad.ldap_hosts.each_with_index do |endpoint, index|
  host, port = endpoint

  puts "  #{index + 1}. #{host}:#{port}"
end

# ============================================================
# LIVE ROLE AND PERMISSION VALIDATION
# ============================================================

accounts.each do |username, expected|

  puts
  puts "=" * 85
  puts "ACCOUNT: #{username.upcase}"
  puts "ROLE:    #{expected[:description]}"
  puts "=" * 85

  started = Process.clock_gettime(
    Process::CLOCK_MONOTONIC
  )

  actual_roles = ad.current_roles(username)

  elapsed = (
    Process.clock_gettime(
      Process::CLOCK_MONOTONIC
    ) - started
  ) * 1000

  durations << elapsed

  puts "Expected roles: #{expected[:roles].inspect}"
  puts "Actual roles:   #{actual_roles.inspect}"
  puts "Execution time: #{elapsed.round(2)} ms"

  # nil represents a directory lookup failure.
  # [] represents a successful lookup with no approved roles.
  #
  # These must not be treated as equivalent.

  roles_match =
    actual_roles.is_a?(Array) &&
    actual_roles.sort == expected[:roles].sort

  if roles_match

    role_passed += 1

    puts "#{coloured_status(true)} Role resolution"

  else

    role_failed += 1

    puts "#{coloured_status(false)} Role resolution"

  end

  puts
  puts "-" * 85

  printf(
    "%-36s %-12s %-12s %s\n",
    "PERMISSION",
    "EXPECTED",
    "ACTUAL",
    "RESULT"
  )

  puts "-" * 85

  granted_count = 0
  denied_count = 0

  permissions.each do |permission|

    expected_granted =
      expected[:permissions].include?(permission)

    actual_granted =
      actual_roles.is_a?(Array) &&
      authorization.allowed?(
        roles: actual_roles,
        permission: permission
      )

    actual_granted = !!actual_granted

    if actual_granted
      granted_count += 1
    else
      denied_count += 1
    end

    # A failed role lookup must not produce a successful
    # validation merely because permissions were denied.

    permission_match =
      actual_roles.is_a?(Array) &&
      actual_granted == expected_granted

    if permission_match
      permission_passed += 1
    else
      permission_failed += 1
    end

    printf(
      "%-36s %-12s %-12s %s\n",
      permission.to_s,
      permission_label(expected_granted),
      permission_label(actual_granted),
      coloured_status(permission_match)
    )

  end

  puts "-" * 85
  puts "Granted permissions: #{granted_count}/#{permissions.size}"
  puts "Denied permissions:  #{denied_count}/#{permissions.size}"

end

# ============================================================
# FINAL VALIDATION SUMMARY
# ============================================================

total_passed = role_passed + permission_passed
total_failed = role_failed + permission_failed
total_checks = total_passed + total_failed

success_rate =
  total_checks.positive? ?
    (total_passed.to_f / total_checks * 100).round(2) :
    0

puts
puts "=" * 85
puts "FINAL RBAC VALIDATION SUMMARY"
puts "=" * 85

puts "Accounts validated:       #{accounts.size}"
puts "Permissions per account:  #{permissions.size}"

puts
puts "ROLE RESOLUTION"

puts "Passed: #{role_passed}"
puts "Failed: #{role_failed}"

puts
puts "EFFECTIVE PERMISSIONS"

puts "Passed: #{permission_passed}"
puts "Failed: #{permission_failed}"

puts
puts "PERFORMANCE"

puts "Minimum: #{durations.min.round(2)} ms"
puts "Maximum: #{durations.max.round(2)} ms"
puts "Average: #{(durations.sum / durations.size).round(2)} ms"

puts
puts "OVERALL RESULTS"

puts "Total checks: #{total_checks}"
puts "Passed:       #{total_passed}"
puts "Failed:       #{total_failed}"
puts "Success rate: #{success_rate}%"

puts

if total_failed.zero?

  puts "#{coloured_status(true)} ALL RBAC VALIDATION CHECKS PASSED"

else

  puts "#{coloured_status(false)} RBAC VALIDATION FAILED"

end

puts "=" * 85

abort "RBAC validation failed" unless total_failed.zero?
