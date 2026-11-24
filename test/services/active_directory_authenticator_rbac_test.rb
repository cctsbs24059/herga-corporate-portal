
# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class ActiveDirectoryAuthenticatorRbacTest < ActiveSupport::TestCase

  USER_DN = "CN=Test User,OU=Users,DC=herga,DC=net"

  def fake_user_entry
    Struct.new(
      :dn,
      :mail,
      :displayname
    ).new(
      USER_DN,
      ["test.user@herga.net"],
      ["Test User"]
    )
  end

  def with_ldap_connection(bind_code: 0)
    ldap = Object.new

    result = Struct.new(:code).new(bind_code)

    ldap.define_singleton_method(:get_operation_result) do
      result
    end

    ldap.define_singleton_method(:open) do |&block|
      block.call(self)
    end

    ActiveDirectoryAuthenticator.stub(
      :connection,
      ldap
    ) do
      yield ldap
    end
  end

  test "authenticates an auditor without employee membership" do
    with_ldap_connection do
      ActiveDirectoryAuthenticator.stub(
        :find_user,
        fake_user_entry
      ) do
        ActiveDirectory::RoleResolver.stub(
          :resolve,
          [:auditor]
        ) do

          identity = ActiveDirectoryAuthenticator.authenticate(
            'HERGA\test.user',
            "test-password"
          )

          assert identity
          assert_equal "test.user", identity.username
          assert_equal [:auditor], identity.roles
          assert_equal false, identity.admin
        end
      end
    end
  end

  test "authenticates multiple AD roles" do
    with_ldap_connection do
      ActiveDirectoryAuthenticator.stub(
        :find_user,
        fake_user_entry
      ) do
        ActiveDirectory::RoleResolver.stub(
          :resolve,
          [:infrastructure_admin, :auditor]
        ) do

          identity = ActiveDirectoryAuthenticator.authenticate(
            'HERGA\test.user',
            "test-password"
          )

          assert_equal(
            [:infrastructure_admin, :auditor],
            identity.roles
          )

          assert_equal false, identity.admin
        end
      end
    end
  end

  test "portal administrator retains administrator identity" do
    with_ldap_connection do
      ActiveDirectoryAuthenticator.stub(
        :find_user,
        fake_user_entry
      ) do
        ActiveDirectory::RoleResolver.stub(
          :resolve,
          [:portal_admin, :employee]
        ) do

          identity = ActiveDirectoryAuthenticator.authenticate(
            'HERGA\test.user',
            "test-password"
          )

          assert_equal true, identity.admin
          assert_includes identity.roles, :portal_admin
        end
      end
    end
  end

  test "authentication rejects users without approved roles" do
    with_ldap_connection do
      ActiveDirectoryAuthenticator.stub(
        :find_user,
        fake_user_entry
      ) do
        ActiveDirectory::RoleResolver.stub(
          :resolve,
          []
        ) do

          assert_nil ActiveDirectoryAuthenticator.authenticate(
            'HERGA\test.user',
            "test-password"
          )
        end
      end
    end
  end

  test "authentication fails closed when role lookup fails" do
    with_ldap_connection do
      ActiveDirectoryAuthenticator.stub(
        :find_user,
        fake_user_entry
      ) do
        ActiveDirectory::RoleResolver.stub(
          :resolve,
          nil
        ) do

          assert_nil ActiveDirectoryAuthenticator.authenticate(
            'HERGA\test.user',
            "test-password"
          )
        end
      end
    end
  end

  test "current roles are retrieved through service account" do
    with_ldap_connection do
      ActiveDirectoryAuthenticator.stub(
        :find_user,
        fake_user_entry
      ) do
        ActiveDirectory::RoleResolver.stub(
          :resolve,
          [:security_admin, :auditor]
        ) do
          ENV.stub(
            :fetch,
            lambda do |key, *|
              case key
              when "HERGA_AD_SERVICE_USER"
                "svc-herga-portal@herga.net"
              when "HERGA_AD_SERVICE_PASSWORD"
                "test-secret"
              else
                raise KeyError, key
              end
            end
          ) do

            assert_equal(
              [:security_admin, :auditor],
              ActiveDirectoryAuthenticator.current_roles(
                "test.user"
              )
            )
          end
        end
      end
    end
  end

  test "legacy current_role returns admin for portal admin" do
    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      [:portal_admin, :auditor]
    ) do
      assert_equal(
        :admin,
        ActiveDirectoryAuthenticator.current_role("test.user")
      )
    end
  end

  test "legacy current_role returns employee for non-admin roles" do
    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      [:auditor]
    ) do
      assert_equal(
        :employee,
        ActiveDirectoryAuthenticator.current_role("test.user")
      )
    end
  end

  test "legacy current_role denies missing membership" do
    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      []
    ) do
      assert_nil ActiveDirectoryAuthenticator.current_role(
        "test.user"
      )
    end
  end

  test "legacy current_role denies directory failure" do
    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      nil
    ) do
      assert_nil ActiveDirectoryAuthenticator.current_role(
        "test.user"
      )
    end
  end

  test "rejects malformed usernames" do
    assert_nil ActiveDirectoryAuthenticator.authenticate(
      "test.user",
      "test-password"
    )

    assert_nil ActiveDirectoryAuthenticator.current_roles(
      "invalid username"
    )
  end

  test "rejects empty passwords" do
    assert_nil ActiveDirectoryAuthenticator.authenticate(
      'HERGA\test.user',
      ""
    )
  end
end
