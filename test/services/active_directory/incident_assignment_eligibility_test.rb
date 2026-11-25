# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class IncidentAssignmentEligibilityTest < ActiveSupport::TestCase
  Service = ActiveDirectory::IncidentAssignmentEligibility

  FakeUser = Struct.new(:id, :username, :admin)
  FakeEntry = Struct.new(:dn, :useraccountcontrol)
  FakeResult = Struct.new(:code)

  setup do
    @ldap = Object.new

    @ldap.define_singleton_method(:get_operation_result) do
      FakeResult.new(0)
    end

    @user = FakeUser.new(
      1,
      "test.user",
      false
    )

    @entry = FakeEntry.new(
      "CN=Test User,DC=herga,DC=net",
      ["512"]
    )
  end

  # ----------------------------------------------------------
  # ROLE-BASED ELIGIBILITY
  # ----------------------------------------------------------

  test "portal administrator is eligible" do
    with_directory_roles([:portal_admin]) do
      assert Service.eligible?(@user)
    end
  end

  test "infrastructure administrator is eligible without local admin flag" do
    with_directory_roles([:infrastructure_admin]) do
      assert Service.eligible?(@user)
    end
  end

  test "security administrator is not eligible" do
    with_directory_roles([:security_admin]) do
      refute Service.eligible?(@user)
    end
  end

  test "auditor is not eligible" do
    with_directory_roles([:auditor]) do
      refute Service.eligible?(@user)
    end
  end

  test "employee is not eligible" do
    with_directory_roles([:employee]) do
      refute Service.eligible?(@user)
    end
  end

  test "multiple roles grant assignment eligibility" do
    with_directory_roles(
      [:infrastructure_admin, :auditor]
    ) do
      assert Service.eligible?(@user)
    end
  end

  test "stale local administrator flag does not grant eligibility" do
    @user.admin = true

    with_directory_roles([:employee]) do
      refute Service.eligible?(@user)
    end
  end

  # ----------------------------------------------------------
  # FAIL-CLOSED ROLE VERIFICATION
  # ----------------------------------------------------------

  test "empty roles deny eligibility" do
    with_directory_roles([]) do
      refute Service.eligible?(@user)
    end
  end

  test "failed role resolution denies eligibility" do
    with_directory_roles(nil) do
      refute Service.eligible?(@user)
    end
  end

  test "unknown role denies eligibility" do
    with_directory_roles([:unknown_role]) do
      refute Service.eligible?(@user)
    end
  end

  test "missing local user denies eligibility" do
    refute Service.eligible?(nil)
  end

  # ----------------------------------------------------------
  # DIRECTORY CONNECTION FAILURE
  # ----------------------------------------------------------

  test "directory connection failure denies eligibility" do
    unavailable_connection = lambda do |**_options, &_block|
      nil
    end

    with_service_credentials do
      ActiveDirectoryAuthenticator.stub(
        :with_connection,
        unavailable_connection
      ) do
        refute Service.eligible?(@user)
      end
    end
  end

  test "nil directory session denies eligibility" do
    invalid_connection = lambda do |**_options, &block|
      block.call(nil)
    end

    with_service_credentials do
      ActiveDirectoryAuthenticator.stub(
        :with_connection,
        invalid_connection
      ) do
        refute Service.eligible?(@user)
      end
    end
  end

  test "nil directory session withholds candidate list" do
    invalid_connection = lambda do |**_options, &block|
      block.call(nil)
    end

    with_service_credentials do
      User.stub(:order, [@user]) do
        ActiveDirectoryAuthenticator.stub(
          :with_connection,
          invalid_connection
        ) do
          assert_nil Service.candidates
        end
      end
    end
  end

  test "missing directory user denies eligibility" do
    with_service_credentials do
      with_connection do
        ActiveDirectoryAuthenticator.stub(
          :find_user,
          nil
        ) do
          refute Service.eligible?(@user)
        end
      end
    end
  end

  test "directory exception denies eligibility" do
    failure = lambda do |**_options, &_block|
      raise IOError, "Directory unavailable"
    end

    with_service_credentials do
      ActiveDirectoryAuthenticator.stub(
        :with_connection,
        failure
      ) do
        refute Service.eligible?(@user)
      end
    end
  end

  # ----------------------------------------------------------
  # CONNECTION LIFECYCLE AND CANDIDATE DISCOVERY
  # ----------------------------------------------------------

  test "candidate assessment uses one directory connection" do
    infrastructure_user =
      FakeUser.new(1, "infrastructure.user", false)

    employee =
      FakeUser.new(2, "employee.user", true)

    users = [infrastructure_user, employee]

    connection_count = 0

    connection = lambda do |**_options, &block|
      connection_count += 1
      block.call(@ldap)
    end

    lookup = lambda do |_ldap, username|
      FakeEntry.new(username, ["512"])
    end

    resolver = lambda do |ldap:, user_dn:|
      assert_equal @ldap, ldap

      if user_dn == "infrastructure.user"
        [:infrastructure_admin]
      else
        [:employee]
      end
    end

    with_service_credentials do
      User.stub(:order, users) do
        ActiveDirectoryAuthenticator.stub(
          :with_connection,
          connection
        ) do
          ActiveDirectoryAuthenticator.stub(
            :find_user,
            lookup
          ) do
            ActiveDirectory::RoleResolver.stub(
              :resolve,
              resolver
            ) do
              assert_equal(
                [infrastructure_user],
                Service.candidates
              )

              assert_equal 1, connection_count
            end
          end
        end
      end
    end
  end

  test "candidate lookup failure does not return partial results" do
    users = [
      FakeUser.new(1, "first.user", false),
      FakeUser.new(2, "second.user", false)
    ]

    lookup = lambda do |_ldap, username|
      FakeEntry.new(username, ["512"])
    end

    resolver = lambda do |ldap:, user_dn:|
      user_dn == "first.user" ?
        [:infrastructure_admin] : nil
    end

    with_service_credentials do
      User.stub(:order, users) do
        with_connection do
          ActiveDirectoryAuthenticator.stub(
            :find_user,
            lookup
          ) do
            ActiveDirectory::RoleResolver.stub(
              :resolve,
              resolver
            ) do
              assert_nil Service.candidates
            end
          end
        end
      end
    end
  end

  test "empty local user register returns empty candidate list" do
    User.stub(:order, []) do
      assert_equal [], Service.candidates
    end
  end

  # ----------------------------------------------------------
  # TEST HELPERS
  # ----------------------------------------------------------

  test "disabled candidate is excluded even with administrator roles" do
    @entry.useraccountcontrol = ["514"]
    with_directory_roles([:portal_admin]) do
      refute Service.eligible?(@user)
      User.stub(:order, [@user]) { assert_equal [], Service.candidates }
    end
  end

  test "missing account status withholds candidate list" do
    @entry.useraccountcontrol = []
    with_directory_roles([:portal_admin]) do
      refute Service.eligible?(@user)
      User.stub(:order, [@user]) { assert_nil Service.candidates }
    end
  end

  private

  def with_service_credentials
    original_fetch = ENV.method(:fetch)

    fetch = lambda do |key, *args, &block|
      case key
      when "HERGA_AD_SERVICE_USER"
        "svc-test@herga.net"
      when "HERGA_AD_SERVICE_PASSWORD"
        "test-password"
      else
        original_fetch.call(key, *args, &block)
      end
    end

    ENV.stub(:fetch, fetch) do
      yield
    end
  end

  def with_connection
    connection = lambda do |**_options, &block|
      block.call(@ldap)
    end

    ActiveDirectoryAuthenticator.stub(
      :with_connection,
      connection
    ) do
      yield
    end
  end

  def with_directory_roles(roles)
    with_service_credentials do
      with_connection do
        ActiveDirectoryAuthenticator.stub(
          :find_user,
          @entry
        ) do
          ActiveDirectory::RoleResolver.stub(
            :resolve,
            roles
          ) do
            yield
          end
        end
      end
    end
  end
end
