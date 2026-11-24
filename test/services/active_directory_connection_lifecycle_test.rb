
# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class ActiveDirectoryConnectionLifecycleTest < ActiveSupport::TestCase

  class FakeLdapSession

    attr_reader :open_count, :close_count, :bind_count

    def initialize(bind_code: 0)
      @bind_code = bind_code
      @open_count = 0
      @close_count = 0
      @bind_count = 0
    end

    def open
      @open_count += 1
      @bind_count += 1

      yield self
    ensure
      @close_count += 1
    end

    def get_operation_result
      Struct.new(:code).new(@bind_code)
    end
  end

  test "opens a single connection and returns workflow result" do
    ldap = FakeLdapSession.new

    ActiveDirectoryAuthenticator.stub(
      :connection,
      ldap
    ) do

      result = ActiveDirectoryAuthenticator.with_connection(
        username: "test@example.test",
        password: "test-password"
      ) do |session|

        assert_same ldap, session

        [:employee]
      end

      assert_equal [:employee], result
      assert_equal 1, ldap.open_count
      assert_equal 1, ldap.bind_count
      assert_equal 1, ldap.close_count
    end
  end

  test "does not execute directory queries after failed bind" do
    ldap = FakeLdapSession.new(bind_code: 49)

    ActiveDirectoryAuthenticator.stub(
      :connection,
      ldap
    ) do

      result = ActiveDirectoryAuthenticator.with_connection(
        username: "test@example.test",
        password: "invalid-password"
      ) do

        flunk "Directory workflow must not execute after failed bind"
      end

      assert_nil result
      assert_equal 1, ldap.open_count
      assert_equal 1, ldap.bind_count
      assert_equal 1, ldap.close_count
    end
  end

  test "closes connection when workflow returns nil" do
    ldap = FakeLdapSession.new

    ActiveDirectoryAuthenticator.stub(
      :connection,
      ldap
    ) do

      result = ActiveDirectoryAuthenticator.with_connection(
        username: "test@example.test",
        password: "test-password"
      ) do
        nil
      end

      assert_nil result
      assert_equal 1, ldap.close_count
    end
  end

  test "closes connection when workflow raises an exception" do
    ldap = FakeLdapSession.new

    ActiveDirectoryAuthenticator.stub(
      :connection,
      ldap
    ) do

      assert_raises(IOError) do
        ActiveDirectoryAuthenticator.with_connection(
          username: "test@example.test",
          password: "test-password"
        ) do

          raise IOError, "Simulated directory failure"
        end
      end

      assert_equal 1, ldap.close_count
    end
  end

  test "rejects empty credentials before opening connection" do
    connection = lambda do |**_options|
      flunk "LDAP connection must not be created"
    end

    ActiveDirectoryAuthenticator.stub(
      :connection,
      connection
    ) do

      assert_nil ActiveDirectoryAuthenticator.with_connection(
        username: "",
        password: "test-password"
      ) { flunk "Unexpected workflow execution" }

      assert_nil ActiveDirectoryAuthenticator.with_connection(
        username: "test@example.test",
        password: ""
      ) { flunk "Unexpected workflow execution" }
    end
  end

  test "authentication fails closed when connection is unavailable" do
    connection = lambda do |**_options|
      raise IOError, "Simulated connection failure"
    end

    ActiveDirectoryAuthenticator.stub(
      :connection,
      connection
    ) do

      assert_nil ActiveDirectoryAuthenticator.authenticate(
        'HERGA\test.user',
        "test-password"
      )
    end
  end

  test "authentication does not perform user lookup after failed bind" do
    ldap = FakeLdapSession.new(bind_code: 49)

    lookup = lambda do |*|
      flunk "User lookup must not execute after failed bind"
    end

    ActiveDirectoryAuthenticator.stub(
      :connection,
      ldap
    ) do
      ActiveDirectoryAuthenticator.stub(
        :find_user,
        lookup
      ) do

        assert_nil ActiveDirectoryAuthenticator.authenticate(
          'HERGA\test.user',
          "test-password"
        )

        assert_equal 1, ldap.bind_count
        assert_equal 1, ldap.close_count
      end
    end
  end

  test "authorisation does not perform user lookup after failed bind" do
    ldap = FakeLdapSession.new(bind_code: 49)

    lookup = lambda do |*|
      flunk "User lookup must not execute after failed bind"
    end

    ENV.stub(
      :fetch,
      lambda do |key, *|
        case key
        when "HERGA_AD_SERVICE_USER"
          "svc-herga-portal@example.test"
        when "HERGA_AD_SERVICE_PASSWORD"
          "test-password"
        else
          raise KeyError, key
        end
      end
    ) do
      ActiveDirectoryAuthenticator.stub(
        :connection,
        ldap
      ) do
        ActiveDirectoryAuthenticator.stub(
          :find_user,
          lookup
        ) do

          assert_nil ActiveDirectoryAuthenticator.current_roles(
            "test.user"
          )

          assert_equal 1, ldap.bind_count
          assert_equal 1, ldap.close_count
        end
      end
    end
  end
end
