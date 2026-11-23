
# frozen_string_literal: true

require "test_helper"

class PortalAuthorizationTest < ActiveSupport::TestCase
  test "defines the five expected roles" do
    assert_equal(
      %i[
        portal_admin
        infrastructure_admin
        security_admin
        auditor
        employee
      ],
      PortalAuthorization::ROLES
    )
  end

  test "portal administrator has every defined permission" do
    PortalAuthorization::PERMISSIONS.each do |permission|
      assert PortalAuthorization.allowed?(
        roles: [:portal_admin],
        permission: permission
      ), "Portal administrator missing #{permission}"
    end
  end

  test "infrastructure administrator can manage infrastructure" do
    assert PortalAuthorization.allowed?(
      roles: [:infrastructure_admin],
      permission: :infrastructure_manage
    )
  end

  test "infrastructure administrator cannot manage governance" do
    refute PortalAuthorization.allowed?(
      roles: [:infrastructure_admin],
      permission: :governance_manage
    )
  end

  test "security administrator can manage governance" do
    assert PortalAuthorization.allowed?(
      roles: [:security_admin],
      permission: :governance_manage
    )
  end

  test "security administrator cannot manage infrastructure" do
    refute PortalAuthorization.allowed?(
      roles: [:security_admin],
      permission: :infrastructure_manage
    )
  end

  test "auditor can download governance evidence" do
    assert PortalAuthorization.allowed?(
      roles: [:auditor],
      permission: :governance_evidence_read
    )
  end

  test "auditor cannot manage governance" do
    refute PortalAuthorization.allowed?(
      roles: [:auditor],
      permission: :governance_manage
    )
  end

  test "auditor cannot manage infrastructure" do
    refute PortalAuthorization.allowed?(
      roles: [:auditor],
      permission: :infrastructure_manage
    )
  end

  test "employee can view the portal" do
    assert PortalAuthorization.allowed?(
      roles: [:employee],
      permission: :portal_read
    )
  end

  test "employee cannot access governance evidence" do
    refute PortalAuthorization.allowed?(
      roles: [:employee],
      permission: :governance_evidence_read
    )
  end

  test "multiple roles combine their permissions" do
    roles = %i[infrastructure_admin auditor]

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

  test "unknown role grants no permissions" do
    refute PortalAuthorization.allowed?(
      roles: [:unknown_role],
      permission: :portal_read
    )
  end

  test "unknown permission is denied" do
    refute PortalAuthorization.allowed?(
      roles: [:portal_admin],
      permission: :delete_everything
    )
  end

  test "nil roles are denied" do
    refute PortalAuthorization.allowed?(
      roles: nil,
      permission: :portal_read
    )
  end

  test "empty roles are denied" do
    refute PortalAuthorization.allowed?(
      roles: [],
      permission: :portal_read
    )
  end

  test "nil permission is denied" do
    refute PortalAuthorization.allowed?(
      roles: [:portal_admin],
      permission: nil
    )
  end

  test "permissions_for removes duplicates" do
    permissions = PortalAuthorization.permissions_for(
      roles: %i[employee auditor]
    )

    assert_equal permissions.uniq, permissions
    assert_includes permissions, :portal_read
    assert_includes permissions, :governance_evidence_read
  end

  test "permissions_for ignores unknown roles" do
    assert_empty PortalAuthorization.permissions_for(
      roles: [:unknown_role]
    )
  end

  test "roles and permissions are immutable" do
    assert_predicate PortalAuthorization::ROLE_PERMISSIONS, :frozen?
    assert_predicate PortalAuthorization::ROLES, :frozen?
    assert_predicate PortalAuthorization::PERMISSIONS, :frozen?

    PortalAuthorization::ROLE_PERMISSIONS.each_value do |permissions|
      assert_predicate permissions, :frozen?
    end
  end

  test "role and permission validation" do
    assert PortalAuthorization.valid_role?(:auditor)
    refute PortalAuthorization.valid_role?(:unknown_role)

    assert PortalAuthorization.valid_permission?(:portal_read)
    refute PortalAuthorization.valid_permission?(:unknown_permission)
  end
end
