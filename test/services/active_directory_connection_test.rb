
# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class ActiveDirectoryConnectionTest < ActiveSupport::TestCase
  test "configured LDAP server list is not empty" do
    assert ActiveDirectoryAuthenticator::LDAP_SERVERS.any?
  end

  test "primary server is the first configured server" do
    assert_equal(
      ActiveDirectoryAuthenticator::LDAP_SERVERS.first,
      ActiveDirectoryAuthenticator::SERVER
    )
  end

  test "LDAP hosts preserve configured server order" do
    expected = ActiveDirectoryAuthenticator::LDAP_SERVERS.map do |server|
      [server, ActiveDirectoryAuthenticator::LDAP_PORT]
    end

    assert_equal(
      expected,
      ActiveDirectoryAuthenticator.ldap_hosts
    )
  end

  test "LDAP port is valid" do
    assert(
      ActiveDirectoryAuthenticator::LDAP_PORT.between?(1, 65_535)
    )
  end

  test "LDAP connection timeout is positive" do
    assert_operator(
      ActiveDirectoryAuthenticator::LDAP_CONNECT_TIMEOUT,
      :>,
      0
    )
  end

  test "LDAP connection receives multiple ordered endpoints" do
    endpoints = [
      ["primary.example.test", 636],
      ["secondary.example.test", 636],
      ["tertiary.example.test", 636]
    ]

    fake_ldap = Object.new

    constructor = lambda do |options|
      assert_equal endpoints, options[:hosts]

      assert_equal(
        ActiveDirectoryAuthenticator::LDAP_CONNECT_TIMEOUT,
        options[:connect_timeout]
      )

      assert_equal(
        :simple_tls,
        options.dig(:encryption, :method)
      )

      assert_equal(
        "test@example.test",
        options.dig(:auth, :username)
      )

      assert_equal(
        "test-password",
        options.dig(:auth, :password)
      )

      fake_ldap
    end

    ActiveDirectoryAuthenticator.stub(:ldap_hosts, endpoints) do
      Net::LDAP.stub(:new, constructor) do
        result = ActiveDirectoryAuthenticator.connection(
          username: "test@example.test",
          password: "test-password"
        )

        assert_same fake_ldap, result
      end
    end
  end

  test "LDAP certificate verification remains mandatory in production" do
    original = ENV["HERGA_LDAP_SKIP_CERT_VERIFY"]
    ENV["HERGA_LDAP_SKIP_CERT_VERIFY"] = "true"

    fake_ldap = Object.new

    constructor = lambda do |options|
      assert_equal(
        OpenSSL::SSL::VERIFY_PEER,
        options.dig(
          :encryption,
          :tls_options,
          :verify_mode
        )
      )

      fake_ldap
    end

    Rails.env.stub(:production?, true) do
      Net::LDAP.stub(:new, constructor) do
        ActiveDirectoryAuthenticator.connection(
          username: "test@example.test",
          password: "test-password"
        )
      end
    end
  ensure
    if original.nil?
      ENV.delete("HERGA_LDAP_SKIP_CERT_VERIFY")
    else
      ENV["HERGA_LDAP_SKIP_CERT_VERIFY"] = original
    end
  end
end
