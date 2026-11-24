
# frozen_string_literal: true

ad = ActiveDirectoryAuthenticator

scenario = ENV.fetch(
  "HERGA_VALIDATION_SCENARIO",
  "Normal operation"
)

expect_outage =
  ENV["HERGA_VALIDATION_EXPECT_OUTAGE"] == "true"

expected_roles = {
  "hu100" => [:employee],
  "hu500" => [:portal_admin]
}

passed = 0
failed = 0

puts "=" * 70
puts "HERGA CORPORATE PORTAL"
puts "ACTIVE DIRECTORY RESILIENCE VALIDATION"
puts "=" * 70

puts "Scenario: #{scenario}"
puts "Environment: #{Rails.env}"
puts "LDAP port: #{ad::LDAP_PORT}"
puts "Connection timeout: #{ad::LDAP_CONNECT_TIMEOUT}s"

puts
puts "Configured authentication servers:"

ad.ldap_hosts.each_with_index do |endpoint, index|
  host, port = endpoint

  puts "  #{index + 1}. #{host}:#{port}"
end

expected_roles.each do |username, expected|

  puts
  puts "-" * 70
  puts "Username: #{username}"
  puts "-" * 70

  expected = nil if expect_outage

  started = Process.clock_gettime(
    Process::CLOCK_MONOTONIC
  )

  begin
    roles = ad.current_roles(username)

    elapsed = (
      Process.clock_gettime(
        Process::CLOCK_MONOTONIC
      ) - started
    ) * 1000

    puts "Expected roles: #{expected.inspect}"
    puts "Actual roles:   #{roles.inspect}"
    puts "Execution time: #{elapsed.round(2)} ms"

    if roles == expected

      if expect_outage
        puts "[PASS] Directory unavailable - access denied"
      else
        puts "[PASS] Role resolution successful"
      end

      passed += 1

    else

      puts "[FAIL] Unexpected role resolution"

      failed += 1

    end

  rescue StandardError => e

    puts "[FAIL] #{e.class}"

    failed += 1

  end
end

puts
puts "=" * 70
puts "VALIDATION SUMMARY"
puts "=" * 70

puts "Scenario: #{scenario}"
puts "Passed checks: #{passed}"
puts "Failed checks: #{failed}"

if failed.zero?
  puts "Overall result: PASS"
else
  puts "Overall result: FAIL"
end

puts "=" * 70

abort "Resilience validation failed" unless failed.zero?
