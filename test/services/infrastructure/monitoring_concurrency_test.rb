
# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "timeout"
require "minitest/mock"

class Infrastructure::MonitoringConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  WAIT_SECONDS = 10
  LOCK_TIMEOUT = "250ms"

  setup do
    @token = SecureRandom.uuid

    @asset = InfrastructureAsset.create!(
      hostname: "HERGA-CONCURRENCY-#{SecureRandom.hex(6)}",
      asset_type: "Linux Server",
      environment: "Test",
      status: "Active",
      source: "Manual"
    )

    @run = InfrastructureMonitoringRun.create!(
      status: "Running",
      total_assets: 1,
      processed_assets: 0,
      reachable_assets: 0,
      unreachable_assets: 0,
      unknown_assets: 0,
      failed_checks: 0,
      started_at: 20.minutes.ago,
      heartbeat_at: 20.minutes.ago,
      execution_token: @token
    )
  end

  teardown do
    return unless @asset && @run

    incident_ids = InfrastructureIncident.where(
      infrastructure_asset_id: @asset.id
    ).select(:id)

    InfrastructureIncidentEvent.where(
      infrastructure_incident_id: incident_ids
    ).delete_all

    InfrastructureIncident.where(
      infrastructure_asset_id: @asset.id
    ).delete_all

    InfrastructureConnectivityResult.where(
      infrastructure_asset_id: @asset.id
    ).delete_all

    InfrastructureAsset.where(id: @asset.id).delete_all

    InfrastructureMonitoringRun.where(
      id: @run.id
    ).delete_all
  end

  # --------------------------------------------------------
  # TEST 1
  # Recovery holds the monitoring-run row lock.
  # A competing transaction cannot acquire it.
  # --------------------------------------------------------

  test "recovery row lock blocks a competing transaction" do
    locked = Queue.new
    release = Queue.new
    errors = Queue.new

    recovery_thread = Thread.new do
      begin
        ActiveRecord::Base.connection_pool.with_connection do
          InfrastructureMonitoringRun.transaction do
            run = InfrastructureMonitoringRun.lock.find(@run.id)

            run.update!(
              status: "Failed",
              completed_at: Time.current,
              error_message: "Confirmed recovery"
            )

            locked << true
            Timeout.timeout(WAIT_SECONDS) { release.pop }
          end
        end
      rescue StandardError => e
        errors << e
      end
    end

    begin
      Timeout.timeout(WAIT_SECONDS) { locked.pop }

      assert_equal "Running", @run.reload.status

      assert_lock_timeout do
        InfrastructureMonitoringRun.lock.find(@run.id)
      end
    ensure
      release << true
      recovery_thread.join(WAIT_SECONDS)
    end

    refute recovery_thread.alive?
    raise errors.pop unless errors.empty?

    @run.reload

    assert_equal "Failed", @run.status
    assert_equal "Confirmed recovery", @run.error_message
    assert_not_nil @run.completed_at
    assert_equal @token, @run.execution_token
  end

  # --------------------------------------------------------
  # TEST 2
  # A worker cannot persist after recovery has committed.
  # --------------------------------------------------------

  test "worker cannot persist after recovery commits" do
    revoke_ownership!

    original_asset = asset_snapshot
    original_results = connectivity_results.count
    original_incidents = incidents.count

    assert_raises(
      Infrastructure::ConnectivityBatchJob::ExecutionOwnershipLost
    ) do
      perform_connectivity_check
    end

    assert_equal original_asset, asset_snapshot
    assert_equal original_results, connectivity_results.count
    assert_equal original_incidents, incidents.count

    assert_equal "Failed", @run.reload.status
    assert_equal @token, @run.execution_token
    assert_equal "Recovery revoked ownership", @run.error_message
  end

  # --------------------------------------------------------
  # TEST 3
  # Worker persistence holds the monitoring-run lock.
  # Recovery cannot revoke ownership until it is released.
  # --------------------------------------------------------

  test "worker persistence blocks concurrent recovery" do
    locked = Queue.new
    release = Queue.new
    errors = Queue.new

    worker_thread = Thread.new do
      begin
        ActiveRecord::Base.connection_pool.with_connection do
          InfrastructureMonitoringRun.transaction do
            run = InfrastructureMonitoringRun.lock.find(@run.id)

            raise "Worker ownership invalid" unless
              run.status == "Running" &&
              run.execution_token == @token

            locked << true
            Timeout.timeout(WAIT_SECONDS) { release.pop }
          end
        end
      rescue StandardError => e
        errors << e
      end
    end

    begin
      Timeout.timeout(WAIT_SECONDS) { locked.pop }

      assert_lock_timeout do
        InfrastructureMonitoringRun.lock.find(@run.id)
      end
    ensure
      release << true
      worker_thread.join(WAIT_SECONDS)
    end

    refute worker_thread.alive?
    raise errors.pop unless errors.empty?

    assert_equal "Running", @run.reload.status
    assert_equal @token, @run.execution_token
  end

  # --------------------------------------------------------
  # TEST 4
  # Recovery commits before the worker attempts persistence.
  # The worker must reject the stale execution token.
  # --------------------------------------------------------

  test "recovery wins the race against worker persistence" do
    recovery_committed = Queue.new
    errors = Queue.new

    recovery_thread = Thread.new do
      begin
        ActiveRecord::Base.connection_pool.with_connection do
          InfrastructureMonitoringRun.transaction do
            run = InfrastructureMonitoringRun.lock.find(@run.id)

            run.update!(
              status: "Failed",
              completed_at: Time.current,
              error_message: "Concurrent recovery"
            )
          end

          recovery_committed << true
        end
      rescue StandardError => e
        errors << e
        recovery_committed << false
      end
    end

    committed = Timeout.timeout(WAIT_SECONDS) do
      recovery_committed.pop
    end

    recovery_thread.join(WAIT_SECONDS)

    assert committed, "Recovery transaction did not commit"
    refute recovery_thread.alive?
    raise errors.pop unless errors.empty?

    original_asset = asset_snapshot

    assert_raises(
      Infrastructure::ConnectivityBatchJob::ExecutionOwnershipLost
    ) do
      perform_connectivity_check
    end

    assert_equal original_asset, asset_snapshot
    assert_equal 0, connectivity_results.count
    assert_equal 0, incidents.count

    assert_equal "Failed", @run.reload.status
    assert_equal "Concurrent recovery", @run.error_message
  end

  # --------------------------------------------------------
  # TEST 5
  # A stale worker cannot resolve an existing incident.
  # Its attempted connectivity check must persist nothing.
  # --------------------------------------------------------

  test "stale worker cannot modify incident state" do
    incident = InfrastructureIncident.create!(
      infrastructure_asset: @asset,
      incident_type: InfrastructureIncident::TYPE_ICMP,
      severity: "Critical",
      status: "Open",
      description: "Connectivity failure",
      first_detected_at: Time.current,
      last_observed_at: Time.current,
      consecutive_failures: 3
    )

    original_status = incident.status
    original_failures = incident.consecutive_failures
    original_events = InfrastructureIncidentEvent.where(
      infrastructure_incident_id: incident.id
    ).count

    revoke_ownership!

    assert_raises(
      Infrastructure::ConnectivityBatchJob::ExecutionOwnershipLost
    ) do
      perform_connectivity_check
    end

    incident.reload

    assert_equal original_status, incident.status
    assert_equal original_failures, incident.consecutive_failures
    assert_nil incident.resolved_at

    assert_equal original_events,
                 InfrastructureIncidentEvent.where(
                   infrastructure_incident_id: incident.id
                 ).count

    assert_equal 0, connectivity_results.count
    assert_equal "Failed", @run.reload.status
  end

  # --------------------------------------------------------
  # TEST 6
  # Two recovery attempts cannot both transition the run.
  # Only one successful transition is permitted.
  # --------------------------------------------------------

  test "concurrent recovery is idempotent" do
    start_gate = Queue.new
    results = Queue.new
    errors = Queue.new

    threads = 2.times.map do
      Thread.new do
        begin
          ActiveRecord::Base.connection_pool.with_connection do
            start_gate.pop

            transitioned = false

            InfrastructureMonitoringRun.transaction do
              run = InfrastructureMonitoringRun.lock.find(@run.id)

              if run.status == "Running"
                run.update!(
                  status: "Failed",
                  completed_at: Time.current,
                  error_message: "Concurrent recovery"
                )

                transitioned = true
              end
            end

            results << transitioned
          end
        rescue StandardError => e
          errors << e
        end
      end
    end

    2.times { start_gate << true }

    threads.each do |thread|
      thread.join(WAIT_SECONDS)
      refute thread.alive?, "Recovery thread did not terminate"
    end

    raise errors.pop unless errors.empty?

    outcomes = 2.times.map do
      Timeout.timeout(WAIT_SECONDS) { results.pop }
    end

    assert_equal 1, outcomes.count(true)
    assert_equal 1, outcomes.count(false)

    @run.reload

    assert_equal "Failed", @run.status
    assert_equal "Concurrent recovery", @run.error_message
    assert_not_nil @run.completed_at
    assert_equal @token, @run.execution_token
  end

  private

  # --------------------------------------------------------
  # PostgreSQL row-lock timeout helper.
  # --------------------------------------------------------

  def assert_lock_timeout
    error = assert_raises(
      ActiveRecord::LockWaitTimeout,
      ActiveRecord::StatementInvalid
    ) do
      InfrastructureMonitoringRun.transaction do
        ActiveRecord::Base.connection.execute(
          "SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'"
        )

        yield
      end
    end

    assert_match(
      /lock timeout|lock not available|canceling statement/i,
      "#{error.message} #{error.cause&.message}"
    )
  end

  # --------------------------------------------------------
  # Revoke ownership through a committed transaction.
  # --------------------------------------------------------

  def revoke_ownership!
    @run.with_lock do
      @run.update!(
        status: "Failed",
        completed_at: Time.current,
        error_message: "Recovery revoked ownership"
      )
    end
  end

  # --------------------------------------------------------
  # Query helpers.
  # --------------------------------------------------------

  def connectivity_results
    InfrastructureConnectivityResult.where(
      infrastructure_asset_id: @asset.id
    )
  end

  def incidents
    InfrastructureIncident.where(
      infrastructure_asset_id: @asset.id
    )
  end

  def asset_snapshot
    @asset.reload.attributes.slice(
      "dns_status",
      "icmp_status",
      "resolved_ip_address",
      "icmp_response_ms",
      "last_connectivity_check_at",
      "connectivity_error"
    )
  end

  # --------------------------------------------------------
  # Simulated connectivity check.
  # No actual network requests are made.
  # --------------------------------------------------------

  def perform_connectivity_check
    successful_status = Object.new

    successful_status.define_singleton_method(:success?) do
      true
    end

    Resolv.stub(:getaddresses, ["192.0.2.10"]) do
      Open3.stub(
        :capture3,
        [
          "64 bytes from 192.0.2.10: time=1.25 ms",
          "",
          successful_status
        ]
      ) do
        Infrastructure::ConnectivityCheck.new(
          @asset,
          monitoring_run: @run,
          execution_token: @token
        ).call
      end
    end
  end
end
