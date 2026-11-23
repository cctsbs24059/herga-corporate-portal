
# frozen_string_literal: true

require "test_helper"

class ActiveDirectoryRoleResolverTest < ActiveSupport::TestCase
  USER_DN = "CN=Test User,OU=Users,DC=herga,DC=net"

  GROUP_ROLES = ActiveDirectory::RoleResolver::GROUP_ROLES

  def resolve_with(memberships, missing_group: nil, failed_group: nil)
    ldap = Object.new

    group_lookup = lambda do |_connection, group_name|
      next nil if group_name == missing_group

      "CN=#{group_name},OU=Groups,DC=herga,DC=net"
    end

    membership_lookup = lambda do |_connection, _user_dn, group_dn|
      group_name = group_dn.split(",", 2).first.delete_prefix("CN=")

      next nil if group_name == failed_group

      memberships.include?(group_name)
    end

    ActiveDirectoryAuthenticator.stub(:group_dn, group_lookup) do
      ActiveDirectoryAuthenticator.stub(
        :member_of?,
        membership_lookup
      ) do
        ActiveDirectory::RoleResolver.resolve(
          ldap: ldap,
          user_dn: USER_DN
        )
      end
    end
  end

  test "defines all five AD role mappings" do
    assert_equal 5, GROUP_ROLES.length

    assert_equal(
      %i[
        portal_admin
        infrastructure_admin
        security_admin
        auditor
        employee
      ],
      GROUP_ROLES.values
    )
  end

  test "resolves portal administrator membership" do
    assert_equal(
      [:portal_admin],
      resolve_with(["HERGA-Portal-Admins"])
    )
  end

  test "resolves infrastructure administrator membership" do
    assert_equal(
      [:infrastructure_admin],
      resolve_with(["HERGA-Portal-Infrastructure-Admins"])
    )
  end

  test "resolves security administrator membership" do
    assert_equal(
      [:security_admin],
      resolve_with(["HERGA-Portal-Security-Admins"])
    )
  end

  test "resolves auditor membership" do
    assert_equal(
      [:auditor],
      resolve_with(["HERGA-Portal-Auditors"])
    )
  end

  test "resolves employee membership" do
    assert_equal(
      [:employee],
      resolve_with(["HERGA-Portal-Users"])
    )
  end

  test "resolves multiple memberships" do
    assert_equal(
      %i[infrastructure_admin auditor employee],
      resolve_with(
        [
          "HERGA-Portal-Infrastructure-Admins",
          "HERGA-Portal-Auditors",
          "HERGA-Portal-Users"
        ]
      )
    )
  end

  test "returns empty roles when membership is absent" do
    assert_equal [], resolve_with([])
  end

  test "fails closed when a configured group is missing" do
    assert_nil resolve_with(
      ["HERGA-Portal-Admins"],
      missing_group: "HERGA-Portal-Auditors"
    )
  end

  test "fails closed when membership verification fails" do
    assert_nil resolve_with(
      ["HERGA-Portal-Admins"],
      failed_group: "HERGA-Portal-Auditors"
    )
  end

  test "rejects a missing LDAP connection" do
    assert_nil ActiveDirectory::RoleResolver.resolve(
      ldap: nil,
      user_dn: USER_DN
    )
  end

  test "rejects an empty user distinguished name" do
    assert_nil ActiveDirectory::RoleResolver.resolve(
      ldap: Object.new,
      user_dn: ""
    )
  end

  test "resolved roles integrate with permission matrix" do
    roles = resolve_with(
      [
        "HERGA-Portal-Infrastructure-Admins",
        "HERGA-Portal-Auditors"
      ]
    )

    assert PortalAuthorization.allowed?(
      roles: roles,
      permission: :infrastructure_manage
    )

    assert PortalAuthorization.allowed?(
      roles: roles,
      permission: :governance_evidence_read
    )

    refute PortalAuthorization.allowed?(
      roles: roles,
      permission: :governance_manage
    )
  end

  test "directory failure grants no permissions" do
    roles = resolve_with(
      ["HERGA-Portal-Admins"],
      failed_group: "HERGA-Portal-Users"
    )

    assert_nil roles

    refute PortalAuthorization.allowed?(
      roles: roles,
      permission: :portal_applications_manage
    )
  end

  test "group mappings are immutable" do
    assert_predicate GROUP_ROLES, :frozen?
  end
end
