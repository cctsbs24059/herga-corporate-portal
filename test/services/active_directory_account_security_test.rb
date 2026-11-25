
# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class ActiveDirectoryAccountSecurityTest < ActiveSupport::TestCase
  Auth = ActiveDirectoryAuthenticator

  # ==========================================================
  # ENABLED ACTIVE DIRECTORY ACCOUNTS
  # ==========================================================

  [512, 544, 66048, 66080].each do |value|
    test "enabled account control #{value}" do
      assert_equal(
        true,
        Auth.account_enabled?(
          { useraccountcontrol: [value.to_s] }
        )
      )
    end
  end

  # ==========================================================
  # DISABLED ACTIVE DIRECTORY ACCOUNTS
  # ==========================================================

  [514, 546, 66050, 66082].each do |value|
    test "disabled account control #{value}" do
      assert_equal(
        false,
        Auth.account_enabled?(
          { useraccountcontrol: [value.to_s] }
        )
      )
    end
  end

  # ==========================================================
  # MISSING OR INVALID ACCOUNT STATUS
  # ==========================================================

  [
    nil,
    [],
    ["invalid"],
    ["512", "514"],
    ["-1"],
    ["0"],
    ["4294967296"]
  ].each_with_index do |value, index|

    test "unverifiable account control #{index}" do
      assert_nil Auth.account_enabled?(
        { useraccountcontrol: value }
      )
    end
  end

  # ==========================================================
  # SECURITY-ENABLED ACTIVE DIRECTORY GROUPS
  # ==========================================================

  [
    -2147483646,
    -2147483644,
    -2147483640
  ].each do |value|

    test "security group #{value}" do
      assert Auth.security_group?(
        { grouptype: [value.to_s] }
      )
    end
  end

  # ==========================================================
  # DISTRIBUTION GROUPS AND INVALID GROUP TYPES
  # ==========================================================

  [
    2,
    4,
    8,
    nil,
    "invalid",
    -2147483649
  ].each_with_index do |value, index|

    test "invalid or distribution group #{index}" do
      refute Auth.security_group?(
        { grouptype: [value] }
      )
    end
  end

  test "missing group type is rejected" do
    refute Auth.security_group?({})
  end

  # ==========================================================
  # ACTIVE DIRECTORY GROUP LOOKUP
  # ==========================================================

  test "group lookup rejects distribution group" do
    entry = Net::LDAP::Entry.new(
      "CN=Test,DC=herga,DC=net"
    )

    entry[:grouptype] = ["2"]

    ldap = Object.new

    ldap.define_singleton_method(:search) do |**|
      [entry]
    end

    ldap.define_singleton_method(:get_operation_result) do
      Struct.new(:code).new(0)
    end

    assert_nil Auth.group_dn(ldap, "Test")
  end

  test "group lookup accepts security group and requests group type" do
    entry = Net::LDAP::Entry.new(
      "CN=Test,DC=herga,DC=net"
    )

    entry[:grouptype] = ["-2147483646"]

    ldap = Object.new

    search_options = nil

    ldap.define_singleton_method(:search) do |**options|
      search_options = options

      [entry]
    end

    ldap.define_singleton_method(:get_operation_result) do
      Struct.new(:code).new(0)
    end

    result = Auth.group_dn(ldap, "Test")

    assert_equal entry.dn, result

    assert_includes(
      search_options.fetch(:attributes),
      "groupType"
    )
  end

  # ==========================================================
  # ACTIVE DIRECTORY USER LOOKUP
  # ==========================================================

  test "user lookup requests mandatory account status" do
    entry = Net::LDAP::Entry.new(
      "CN=Test,DC=herga,DC=net"
    )

    ldap = Object.new

    search_options = nil

    ldap.define_singleton_method(:search) do |**options|
      search_options = options

      [entry]
    end

    ldap.define_singleton_method(:get_operation_result) do
      Struct.new(:code).new(0)
    end

    result = Auth.find_user(ldap, "test")

    assert_same entry, result

    assert_includes(
      search_options.fetch(:attributes),
      "userAccountControl"
    )
  end

  # ==========================================================
  # FAIL-CLOSED GROUP MEMBERSHIP VERIFICATION
  # ==========================================================

  test "nil membership search fails closed" do
    ldap = Object.new

    ldap.define_singleton_method(:search) do |**|
      nil
    end

    ldap.define_singleton_method(:get_operation_result) do
      Struct.new(:code).new(0)
    end

    assert_nil Auth.member_of?(
      ldap,
      "CN=User",
      "CN=Group"
    )
  end
end
