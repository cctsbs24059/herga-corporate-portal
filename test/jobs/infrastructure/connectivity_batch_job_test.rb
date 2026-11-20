
# frozen_string_literal: true

require "test_helper"
require "securerandom"

class Infrastructure::ConnectivityBatchJobTest < ActiveSupport::TestCase
  setup do
    @job = Infrastructure::ConnectivityBatchJob.new
    @execution_token = SecureRandom.uuid
  end

  # ----------------------------------------------------------
  # TEST 1
  # A Queued monitoring run can be claimed and completed.
  # ----------------------------------------------------------

  test "completes an empty monitoring batch" do
    run = create_run(status: "Queued", total_assets: 0)

    @job.perform(run.id, [])

    run.reload

    assert_equal "Completed", run.status
    assert_not_nil run.execution_token
    assert_not_nil run.started_at
    assert_not_nil run.completed_at
    assert_not_nil run.heartbeat_at
    assert_equal 0, run.processed_assets
  end

  # ----------------------------------------------------------
  # TEST 2
  # A duplicate execution cannot reclaim a completed run.
  # ----------------------------------------------------------

  test "duplicate execution cannot claim a completed run" do
    run = create_run(status: "Queued", total_assets: 0)

    @job.perform(run.id, [])

    run.reload

    original_token = run.execution_token
    original_started_at = run.started_at
    original_completed_at = run.completed_at

    @job.perform(run.id, [])

    run.reload

    assert_equal "Completed", run.status
    assert_equal original_token, run.execution_token
    assert_equal original_started_at, run.started_at
    assert_equal original_completed_at, run.completed_at
  end

  # ----------------------------------------------------------
  # TEST 3
  # A recovered Failed run cannot be claimed.
  # ----------------------------------------------------------

  test "does not execute a recovered failed run" do
    run = create_run(status: "Failed", total_assets: 0)

    @job.perform(run.id, [])

    run.reload

    assert_equal "Failed", run.status
    assert_nil run.execution_token
    assert_nil run.started_at
    assert_nil run.completed_at
  end

  # ----------------------------------------------------------
  # TEST 4
  # A recovered run rejects heartbeat updates.
  # ----------------------------------------------------------

  test "heartbeat rejects a run that is no longer running" do
    run = create_owned_run(total_assets: 1)

    run.update!(
      heartbeat_at: 5.minutes.ago
    )

    original_heartbeat = run.reload.heartbeat_at

    run.update!(status: "Failed")

    assert_raises(
      Infrastructure::ConnectivityBatchJob::ExecutionOwnershipLost
    ) do
      @job.send(
        :refresh_heartbeat!,
        run.id,
        @execution_token
      )
    end

    run.reload

    assert_equal "Failed", run.status
    assert_equal original_heartbeat, run.heartbeat_at
  end

  # ----------------------------------------------------------
  # TEST 5
  # Progress counters cannot change after recovery.
  # ----------------------------------------------------------

  test "progress counters remain unchanged after ownership is lost" do
    run = create_owned_run(total_assets: 3)

    run.update!(
      processed_assets: 1,
      reachable_assets: 1
    )

    run.update!(status: "Failed")

    assert_raises(
      Infrastructure::ConnectivityBatchJob::ExecutionOwnershipLost
    ) do
      @job.send(
        :record_progress!,
        run.id,
        execution_token: @execution_token,
        processed: 1,
        unreachable: 1
      )
    end

    run.reload

    assert_equal "Failed", run.status
    assert_equal 1, run.processed_assets
    assert_equal 1, run.reachable_assets
    assert_equal 0, run.unreachable_assets
    assert_equal 0, run.failed_checks
  end

  # ----------------------------------------------------------
  # TEST 6
  # A recovered run cannot transition to Completed.
  # ----------------------------------------------------------

  test "failed monitoring run cannot transition to completed" do
    run = create_owned_run(total_assets: 1)

    run.update!(status: "Failed")

    assert_raises(
      Infrastructure::ConnectivityBatchJob::ExecutionOwnershipLost
    ) do
      @job.send(
        :complete_run!,
        run.id,
        @execution_token
      )
    end

    run.reload

    assert_equal "Failed", run.status
    assert_nil run.completed_at
  end

  # ----------------------------------------------------------
  # TEST 7
  # Progress counters update correctly for the owning worker.
  # ----------------------------------------------------------

  test "records successful progress while running" do
    run = create_owned_run(total_assets: 3)

    @job.send(
      :record_progress!,
      run.id,
      execution_token: @execution_token,
      processed: 1,
      reachable: 1
    )

    @job.send(
      :record_progress!,
      run.id,
      execution_token: @execution_token,
      processed: 1,
      unreachable: 1
    )

    @job.send(
      :record_progress!,
      run.id,
      execution_token: @execution_token,
      processed: 1,
      unknown: 1
    )

    run.reload

    assert_equal 3, run.processed_assets
    assert_equal 1, run.reachable_assets
    assert_equal 1, run.unreachable_assets
    assert_equal 1, run.unknown_assets
    assert_equal 0, run.failed_checks
    assert_not_nil run.heartbeat_at
  end

  # ----------------------------------------------------------
  # TEST 8
  # The owning worker can complete its monitoring run.
  # ----------------------------------------------------------

  test "running monitoring run transitions to completed" do
    run = create_owned_run(total_assets: 0)

    @job.send(
      :complete_run!,
      run.id,
      @execution_token
    )

    run.reload

    assert_equal "Completed", run.status
    assert_equal @execution_token, run.execution_token
    assert_not_nil run.completed_at
    assert_not_nil run.heartbeat_at
  end

  # ----------------------------------------------------------
  # TEST 9
  # A worker failure cannot overwrite a recovery decision.
  # ----------------------------------------------------------

  test "failure handler preserves a recovered terminal state" do
    run = create_owned_run(total_assets: 1)

    run.update!(
      status: "Failed",
      error_message: "Recovered by monitoring supervisor"
    )

    @job.send(
      :fail_run!,
      run.id,
      @execution_token,
      StandardError.new("Worker failure")
    )

    run.reload

    assert_equal "Failed", run.status

    assert_equal(
      "Recovered by monitoring supervisor",
      run.error_message
    )
  end

  # ----------------------------------------------------------
  # TEST 10
  # A worker with an incorrect token cannot update progress.
  # ----------------------------------------------------------

  test "rejects progress updates from a different execution token" do
    run = create_owned_run(total_assets: 2)

    incorrect_token = SecureRandom.uuid

    assert_raises(
      Infrastructure::ConnectivityBatchJob::ExecutionOwnershipLost
    ) do
      @job.send(
        :record_progress!,
        run.id,
        execution_token: incorrect_token,
        processed: 1,
        reachable: 1
      )
    end

    run.reload

    assert_equal "Running", run.status
    assert_equal @execution_token, run.execution_token
    assert_equal 0, run.processed_assets
    assert_equal 0, run.reachable_assets
  end

  # ----------------------------------------------------------
  # TEST 11
  # A worker with an incorrect token cannot complete a run.
  # ----------------------------------------------------------

  test "rejects completion from a different execution token" do
    run = create_owned_run(total_assets: 0)

    incorrect_token = SecureRandom.uuid

    assert_raises(
      Infrastructure::ConnectivityBatchJob::ExecutionOwnershipLost
    ) do
      @job.send(
        :complete_run!,
        run.id,
        incorrect_token
      )
    end

    run.reload

    assert_equal "Running", run.status
    assert_equal @execution_token, run.execution_token
    assert_nil run.completed_at
  end

  private

  # ----------------------------------------------------------
  # Create a monitoring run with the requested status.
  # ----------------------------------------------------------

  def create_run(status:, total_assets:)
    InfrastructureMonitoringRun.create!(
      status: status,
      total_assets: total_assets
    )
  end

  # ----------------------------------------------------------
  # Create a Running monitoring run owned by a worker.
  # ----------------------------------------------------------

  def create_owned_run(total_assets:)
    InfrastructureMonitoringRun.create!(
      status: "Running",
      total_assets: total_assets,
      execution_token: @execution_token,
      started_at: Time.current,
      heartbeat_at: Time.current
    )
  end
end
