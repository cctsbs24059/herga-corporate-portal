
# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "minitest/mock"

class Infrastructure::ConnectivityCheckTest < ActiveSupport::TestCase
  setup do
    @asset = InfrastructureAsset.create!(
      hostname: "fencing-#{SecureRandom.hex(6)}",
      fqdn: "fencing-#{SecureRandom.hex(6)}.example.test",
      asset_type: "Linux Server",
      environment: "Test",
      status: "Active",
      source: "Manual"
    )

    @token = SecureRandom.uuid
  end

  # ----------------------------------------------------------
  # TEST 1
  # A Failed monitoring run cannot persist connectivity data.
  # ----------------------------------------------------------

  test "rejects persistence when monitoring run has failed" do
    run = create_run(
      status: "Failed",
      execution_token: @token
    )

    assert_no_persistence(run, @token)
  end

  # ----------------------------------------------------------
  # TEST 2
  # A worker with an incorrect token cannot persist results.
  # ----------------------------------------------------------

  test "rejects persistence when execution token is incorrect" do
    run = create_run(
      status: "Running",
      execution_token: @token
    )

    assert_no_persistence(run, SecureRandom.uuid)
  end

  # ----------------------------------------------------------
  # TEST 3
  # A batch check requires an execution token.
  # ----------------------------------------------------------

  test "rejects persistence when execution token is missing" do
    run = create_run(
      status: "Running",
      execution_token: @token
    )

    original_asset = asset_status_snapshot

    assert_raises(ArgumentError) do
      perform_check(run: run, token: nil)
    end

    assert_equal 0, results_for_asset.count
    assert_equal original_asset, asset_status_snapshot
    assert_equal 0, incidents_for_asset.count
  end

  # ----------------------------------------------------------
  # TEST 4
  # Recovery must revoke the worker's persistence permission.
  # ----------------------------------------------------------

  test "rejects persistence after recovery revokes ownership" do
    run = create_run(
      status: "Running",
      execution_token: @token
    )

    run.update!(
      status: "Failed",
      completed_at: Time.current,
      error_message: "Recovered by supervisor"
    )

    assert_no_persistence(run, @token)

    run.reload

    assert_equal "Failed", run.status
    assert_equal "Recovered by supervisor", run.error_message
  end

  # ----------------------------------------------------------
  # TEST 5
  # The owning worker can persist connectivity results.
  # ----------------------------------------------------------

  test "accepts persistence from the owning worker" do
    run = create_run(
      status: "Running",
      execution_token: @token
    )

    assert_difference(
      -> { results_for_asset.count },
      1
    ) do
      perform_check(run: run, token: @token)
    end

    result = results_for_asset.order(:id).last

    assert_not_nil result
    assert_equal run.id, result.infrastructure_monitoring_run_id
    assert_equal @asset.id, result.infrastructure_asset_id
    assert_equal "Resolved", result.dns_status
    assert_equal "Reachable", result.icmp_status
    assert_equal "192.0.2.10", result.resolved_ip_address
    assert_in_delta 1.25, result.icmp_response_ms, 0.001
    assert_not_nil result.checked_at

    @asset.reload

    assert_equal "Resolved", @asset.dns_status
    assert_equal "Reachable", @asset.icmp_status
    assert_equal "192.0.2.10", @asset.resolved_ip_address
    assert_in_delta 1.25, @asset.icmp_response_ms, 0.001
    assert_not_nil @asset.last_connectivity_check_at

    assert_equal "Running", run.reload.status
    assert_equal @token, run.execution_token
  end

  # ----------------------------------------------------------
  # TEST 6
  # Standalone checks must work without monitoring ownership.
  # ----------------------------------------------------------

  test "standalone connectivity checks work without monitoring ownership" do
    assert_difference(
      -> { results_for_asset.count },
      1
    ) do
      perform_check(run: nil, token: nil)
    end

    result = results_for_asset.order(:id).last

    assert_not_nil result
    assert_nil result.infrastructure_monitoring_run_id
    assert_equal "Resolved", result.dns_status
    assert_equal "Reachable", result.icmp_status
    assert_equal "192.0.2.10", result.resolved_ip_address

    @asset.reload

    assert_equal "Resolved", @asset.dns_status
    assert_equal "Reachable", @asset.icmp_status
    assert_not_nil @asset.last_connectivity_check_at
  end

  private

  # ----------------------------------------------------------
  # Helper: Create a monitoring run.
  # ----------------------------------------------------------

  def create_run(attributes = {})
    InfrastructureMonitoringRun.create!(
      {
        status: "Running",
        total_assets: 1,
        started_at: Time.current,
        heartbeat_at: Time.current
      }.merge(attributes)
    )
  end

  # ----------------------------------------------------------
  # Helper: Retrieve connectivity history for the test asset.
  # ----------------------------------------------------------

  def results_for_asset
    InfrastructureConnectivityResult.where(
      infrastructure_asset_id: @asset.id
    )
  end

  # ----------------------------------------------------------
  # Helper: Retrieve incidents for the test asset.
  # ----------------------------------------------------------

  def incidents_for_asset
    InfrastructureIncident.where(
      infrastructure_asset_id: @asset.id
    )
  end

  # ----------------------------------------------------------
  # Helper: Capture the persisted asset connectivity status.
  # ----------------------------------------------------------

  def asset_status_snapshot
    @asset.reload.attributes.slice(
      "dns_status",
      "icmp_status",
      "resolved_ip_address",
      "icmp_response_ms",
      "last_connectivity_check_at",
      "connectivity_error"
    )
  end

  # ----------------------------------------------------------
  # Helper: Simulate DNS and ICMP without network requests.
  # ----------------------------------------------------------

  def perform_check(run:, token:)
    Resolv.stub(:getaddresses, ["192.0.2.10"]) do
      Open3.stub(
        :capture3,
        [
          "64 bytes from 192.0.2.10: time=1.25 ms",
          "",
          successful_ping_status
        ]
      ) do
        Infrastructure::ConnectivityCheck.new(
          @asset,
          monitoring_run: run,
          execution_token: token
        ).call
      end
    end
  end

  # ----------------------------------------------------------
  # Helper: Simulate a successful ping exit status.
  # ----------------------------------------------------------

  def successful_ping_status
    status = Object.new

    status.define_singleton_method(:success?) do
      true
    end

    status
  end

  # ----------------------------------------------------------
  # Helper: Verify that rejected execution persists nothing.
  # ----------------------------------------------------------

  def assert_no_persistence(run, token)
    original_asset = asset_status_snapshot
    original_results = results_for_asset.count
    original_incidents = incidents_for_asset.count

    assert_raises(
      Infrastructure::ConnectivityBatchJob::ExecutionOwnershipLost
    ) do
      perform_check(run: run, token: token)
    end

    assert_equal original_results, results_for_asset.count
    assert_equal original_incidents, incidents_for_asset.count
    assert_equal original_asset, asset_status_snapshot
  end
end
