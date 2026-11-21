
# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class Infrastructure::StaleMonitoringRunRecoveryJobTest < ActiveSupport::TestCase
  setup do
    @job = Infrastructure::StaleMonitoringRunRecoveryJob.new
    @original_flag = ENV["HERGA_MONITORING_RECOVERY_ENABLED"]
  end

  teardown do
    if @original_flag.nil?
      ENV.delete("HERGA_MONITORING_RECOVERY_ENABLED")
    else
      ENV["HERGA_MONITORING_RECOVERY_ENABLED"] = @original_flag
    end
  end

  # ----------------------------------------------------------
  # TEST 1
  # Recovery must remain disabled when the feature flag
  # is absent.
  # ----------------------------------------------------------

  test "does not execute recovery when feature flag is absent" do
    ENV.delete("HERGA_MONITORING_RECOVERY_ENABLED")

    recovery = Minitest::Mock.new

    Infrastructure::StaleMonitoringRunRecovery.stub(
      :new, -> { recovery }
    ) do
      assert_nil @job.perform
    end

    recovery.verify
  end

  # ----------------------------------------------------------
  # TEST 2
  # Recovery must remain disabled when the feature flag
  # is explicitly set to false.
  # ----------------------------------------------------------

  test "does not execute recovery when feature flag is false" do
    ENV["HERGA_MONITORING_RECOVERY_ENABLED"] = "false"

    recovery = Minitest::Mock.new

    Infrastructure::StaleMonitoringRunRecovery.stub(
      :new, -> { recovery }
    ) do
      assert_nil @job.perform
    end

    recovery.verify
  end

  # ----------------------------------------------------------
  # TEST 3
  # Recovery must execute exactly once when enabled.
  #
  # The mock expectation verifies the service call.
  # We do not assert the job's return value because
  # Rails.logger.info may return true.
  # ----------------------------------------------------------

  test "executes recovery once when feature flag is true" do
    ENV["HERGA_MONITORING_RECOVERY_ENABLED"] = "true"

    recovery = Minitest::Mock.new
    recovery.expect(:call, nil)

    Infrastructure::StaleMonitoringRunRecovery.stub(
      :new, -> { recovery }
    ) do
      @job.perform
    end

    recovery.verify
  end

  # ----------------------------------------------------------
  # TEST 4
  # Unexpected recovery service failures must propagate.
  #
  # This allows Solid Queue to record the failed job.
  # ----------------------------------------------------------

  test "propagates recovery service failures" do
    ENV["HERGA_MONITORING_RECOVERY_ENABLED"] = "true"

    recovery = Object.new

    recovery.define_singleton_method(:call) do
      raise StandardError, "Simulated recovery failure"
    end

    Infrastructure::StaleMonitoringRunRecovery.stub(
      :new, -> { recovery }
    ) do
      error = assert_raises(StandardError) do
        @job.perform
      end

      assert_equal(
        "Simulated recovery failure",
        error.message
      )
    end
  end
end
