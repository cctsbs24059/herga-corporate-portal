
# frozen_string_literal: true

require "test_helper"

class Infrastructure::StaleMonitoringRunRecoveryTest < ActiveSupport::TestCase
  setup do
    @service = Infrastructure::StaleMonitoringRunRecovery.new
  end

  test "does not recover a recent running monitoring run" do
    run = create_run(
      status: "Running",
      heartbeat_at: Time.current,
      active_job_id: SecureRandom.uuid
    )

    @service.call

    assert_equal "Running", run.reload.status
    assert_nil run.completed_at
  end

  test "does not recover a stale running run with missing job identifier" do
    run = create_run(
      status: "Running",
      heartbeat_at: 20.minutes.ago,
      active_job_id: nil
    )

    @service.call

    assert_equal "Running", run.reload.status
    assert_nil run.completed_at
  end

  test "does not recover a stale run when Solid Queue job is missing" do
    run = create_run(
      status: "Running",
      heartbeat_at: 20.minutes.ago,
      active_job_id: SecureRandom.uuid
    )

    SolidQueue::Job.stub(:find_by, nil) do
      @service.call
    end

    assert_equal "Running", run.reload.status
    assert_nil run.completed_at
  end

  test "does not recover a stale run with a claimed execution" do
    run = create_run(
      status: "Running",
      heartbeat_at: 20.minutes.ago,
      active_job_id: SecureRandom.uuid
    )

    job = fake_job

    SolidQueue::Job.stub(:find_by, job) do
      SolidQueue::ReadyExecution.stub(:exists?, false) do
        SolidQueue::ScheduledExecution.stub(:exists?, false) do
          SolidQueue::ClaimedExecution.stub(:exists?, true) do
            @service.call
          end
        end
      end
    end

    assert_equal "Running", run.reload.status
  end

  test "does not recover a stale queued run with a ready execution" do
    run = create_run(
      status: "Queued",
      active_job_id: SecureRandom.uuid
    )

    run.update_columns(
      created_at: 20.minutes.ago,
      updated_at: 20.minutes.ago
    )

    job = fake_job

    SolidQueue::Job.stub(:find_by, job) do
      SolidQueue::ReadyExecution.stub(:exists?, true) do
        @service.call
      end
    end

    assert_equal "Queued", run.reload.status
  end

  test "recovers a stale running run with confirmed failed execution" do
    run = create_run(
      status: "Running",
      heartbeat_at: 20.minutes.ago,
      active_job_id: SecureRandom.uuid
    )

    with_failed_job do
      @service.call
    end

    run.reload

    assert_equal "Failed", run.status
    assert_not_nil run.completed_at
    assert_equal "Associated Solid Queue job failed",
                 run.error_message
  end

  test "recovers a stale queued run with confirmed failed execution" do
    run = create_run(
      status: "Queued",
      active_job_id: SecureRandom.uuid
    )

    run.update_columns(
      created_at: 20.minutes.ago,
      updated_at: 20.minutes.ago
    )

    with_failed_job do
      @service.call
    end

    assert_equal "Failed", run.reload.status
    assert_not_nil run.completed_at
  end

  test "does not modify completed monitoring runs" do
    run = create_run(
      status: "Completed",
      completed_at: Time.current
    )

    @service.call

    assert_equal "Completed", run.reload.status
  end

  test "does not repeat recovery after a run has failed" do
    run = create_run(
      status: "Running",
      heartbeat_at: 20.minutes.ago,
      active_job_id: SecureRandom.uuid
    )

    with_failed_job do
      @service.call
      first_completed_at = run.reload.completed_at

      @service.call

      assert_equal "Failed", run.reload.status
      assert_equal first_completed_at, run.completed_at
    end
  end

  private

  def create_run(attributes = {})
    InfrastructureMonitoringRun.create!(
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
  end

  def fake_job
    Struct.new(:id, :finished_at).new(123_456, nil)
  end

  def with_failed_job(&block)
    job = fake_job

    SolidQueue::Job.stub(:find_by, job) do
      SolidQueue::ReadyExecution.stub(:exists?, false) do
        SolidQueue::ScheduledExecution.stub(:exists?, false) do
          SolidQueue::ClaimedExecution.stub(:exists?, false) do
            SolidQueue::FailedExecution.stub(:exists?, true) do
              block.call
            end
          end
        end
      end
    end
  end
end
