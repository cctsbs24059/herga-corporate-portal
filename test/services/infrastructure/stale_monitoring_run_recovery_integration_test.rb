
# frozen_string_literal: true

require "test_helper"
require "securerandom"

class Infrastructure::StaleMonitoringRunRecoveryIntegrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @service = Infrastructure::StaleMonitoringRunRecovery.new

    @created_run_ids = []
    @created_job_ids = []
    @created_process_ids = []
  end

  teardown do
    # Remove execution records belonging only to jobs created
    # by this test.

    if @created_job_ids.any?
      [
        SolidQueue::ReadyExecution,
        SolidQueue::ScheduledExecution,
        SolidQueue::ClaimedExecution,
        SolidQueue::FailedExecution,
        SolidQueue::BlockedExecution
      ].each do |model|
        model.where(job_id: @created_job_ids).delete_all
      end

      SolidQueue::Job
        .where(id: @created_job_ids)
        .delete_all
    end

    # Remove test worker processes.
    SolidQueue::Process
      .where(id: @created_process_ids)
      .delete_all

    # Remove monitoring runs created by these tests.
    InfrastructureMonitoringRun
      .where(id: @created_run_ids)
      .delete_all
  end

  # ---------------------------------------------------------
  # TEST 1
  # Ready executions must not trigger recovery.
  # ---------------------------------------------------------

  test "real ready execution preserves stale queued run" do
    run, job = create_run_with_job(status: "Queued")

    make_queued_run_stale(run)

    # Solid Queue automatically creates a ready execution
    # when a job is inserted with a past scheduled_at value.
    assert SolidQueue::ReadyExecution.exists?(job_id: job.id)

    @service.call

    assert_equal "Queued", run.reload.status
    assert_nil run.completed_at
  end

  # ---------------------------------------------------------
  # TEST 2
  # Scheduled executions must not trigger recovery.
  # ---------------------------------------------------------

  test "real scheduled execution preserves stale queued run" do
    run, job = create_run_with_job(status: "Queued")

    make_queued_run_stale(run)

    clear_executions(job)

    SolidQueue::ScheduledExecution.create!(
      job: job,
      queue_name: job.queue_name,
      priority: job.priority,
      scheduled_at: 5.minutes.from_now
    )

    @service.call

    assert_equal "Queued", run.reload.status
    assert_nil run.completed_at

    assert SolidQueue::ScheduledExecution.exists?(
      job_id: job.id
    )
  end

  # ---------------------------------------------------------
  # TEST 3
  # Claimed executions must not trigger recovery.
  # ---------------------------------------------------------

  test "real claimed execution preserves stale running run" do
    run, job = create_run_with_job(status: "Running")

    clear_executions(job)

    process = create_process

    SolidQueue::ClaimedExecution.create!(
      job: job,
      process: process
    )

    @service.call

    assert_equal "Running", run.reload.status
    assert_nil run.completed_at

    assert SolidQueue::ClaimedExecution.exists?(
      job_id: job.id
    )
  end

  # ---------------------------------------------------------
  # TEST 4
  # Confirmed failed execution must recover a running run.
  # ---------------------------------------------------------

  test "real failed execution recovers stale running run" do
    run, job = create_run_with_job(status: "Running")

    clear_executions(job)

    SolidQueue::FailedExecution.create!(
      job: job,
      error: "Integration test worker failure"
    )

    @service.call

    run.reload

    assert_equal "Failed", run.status
    assert_not_nil run.completed_at

    assert_equal(
      "Associated Solid Queue job failed",
      run.error_message
    )
  end

  # ---------------------------------------------------------
  # TEST 5
  # Confirmed failed execution must recover a queued run.
  # ---------------------------------------------------------

  test "real failed execution recovers stale queued run" do
    run, job = create_run_with_job(status: "Queued")

    make_queued_run_stale(run)

    clear_executions(job)

    SolidQueue::FailedExecution.create!(
      job: job,
      error: "Integration test enqueue failure"
    )

    @service.call

    run.reload

    assert_equal "Failed", run.status
    assert_not_nil run.completed_at
  end

  # ---------------------------------------------------------
  # TEST 6
  # Finished jobs without failure evidence remain unverified.
  # ---------------------------------------------------------

  test "real finished job remains unverified" do
    run, job = create_run_with_job(status: "Running")

    clear_executions(job)

    job.update!(
      finished_at: Time.current
    )

    @service.call

    assert_equal "Running", run.reload.status
    assert_nil run.completed_at
    assert_not_nil job.reload.finished_at
  end

  # ---------------------------------------------------------
  # TEST 7
  # Missing queue jobs must not cause speculative recovery.
  # ---------------------------------------------------------

  test "missing real queue job preserves stale running run" do
    run = create_run(
      status: "Running",
      started_at: 20.minutes.ago,
      heartbeat_at: 20.minutes.ago,
      active_job_id: SecureRandom.uuid
    )

    @service.call

    assert_equal "Running", run.reload.status
    assert_nil run.completed_at
  end

  # ---------------------------------------------------------
  # TEST 8
  # Repeated recovery must be idempotent.
  # ---------------------------------------------------------

  test "real failed execution recovery is idempotent" do
    run, job = create_run_with_job(status: "Running")

    clear_executions(job)

    SolidQueue::FailedExecution.create!(
      job: job,
      error: "Integration test failure"
    )

    @service.call

    run.reload

    first_completed_at = run.completed_at

    assert_equal "Failed", run.status
    assert_not_nil first_completed_at

    @service.call

    run.reload

    assert_equal "Failed", run.status
    assert_equal first_completed_at, run.completed_at

    assert_equal(
      "Associated Solid Queue job failed",
      run.error_message
    )
  end

  # ---------------------------------------------------------
  # TEST 9
  # Active execution evidence takes precedence over failure.
  # ---------------------------------------------------------

  test "real ready execution takes precedence over failure evidence" do
    run, job = create_run_with_job(status: "Running")

    # Preserve the ready execution created automatically
    # by Solid Queue.
    assert SolidQueue::ReadyExecution.exists?(
      job_id: job.id
    )

    # Deliberately create conflicting evidence to test
    # conservative recovery behaviour.
    SolidQueue::FailedExecution.create!(
      job: job,
      error: "Conflicting test execution state"
    )

    @service.call

    assert_equal "Running", run.reload.status
    assert_nil run.completed_at
  end

  private

  # ---------------------------------------------------------
  # Monitoring run factory
  # ---------------------------------------------------------

  def create_run(attributes = {})
    run = InfrastructureMonitoringRun.create!(
      {
        status: "Queued",
        total_assets: 1,
        processed_assets: 0,
        reachable_assets: 0,
        unreachable_assets: 0,
        unknown_assets: 0,
        failed_checks: 0
      }.merge(attributes)
    )

    @created_run_ids << run.id

    run
  end

  # ---------------------------------------------------------
  # Monitoring run and Solid Queue job factory
  # ---------------------------------------------------------

  def create_run_with_job(status:)
    active_job_id = SecureRandom.uuid

    attributes = {
      status: status,
      active_job_id: active_job_id,
      execution_token: SecureRandom.uuid
    }

    if status == "Running"
      attributes[:started_at] = 20.minutes.ago
      attributes[:heartbeat_at] = 20.minutes.ago
    end

    run = create_run(attributes)

    job = SolidQueue::Job.create!(
      queue_name: "integration_test",
      class_name: "Infrastructure::ConnectivityBatchJob",
      priority: 0,
      active_job_id: active_job_id,
      scheduled_at: 20.minutes.ago
    )

    @created_job_ids << job.id

    [run, job]
  end

  # ---------------------------------------------------------
  # Solid Queue worker process factory
  # ---------------------------------------------------------

  def create_process
    process = SolidQueue::Process.create!(
      kind: "Worker",
      name: "integration-test-#{SecureRandom.hex(8)}",
      pid: Process.pid,
      hostname: "integration-test",
      last_heartbeat_at: Time.current
    )

    @created_process_ids << process.id

    process
  end

  # ---------------------------------------------------------
  # Clear automatically generated execution states
  # ---------------------------------------------------------

  def clear_executions(job)
    [
      SolidQueue::ReadyExecution,
      SolidQueue::ScheduledExecution,
      SolidQueue::ClaimedExecution,
      SolidQueue::FailedExecution,
      SolidQueue::BlockedExecution
    ].each do |model|
      model.where(job_id: job.id).delete_all
    end
  end

  # ---------------------------------------------------------
  # Simulate an old queued monitoring run
  # ---------------------------------------------------------

  def make_queued_run_stale(run)
    run.update_columns(
      created_at: 20.minutes.ago,
      updated_at: 20.minutes.ago
    )
  end
end
