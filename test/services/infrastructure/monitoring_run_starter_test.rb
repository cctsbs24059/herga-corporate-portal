
# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "securerandom"

class Infrastructure::MonitoringRunStarterTest < ActiveSupport::TestCase
  setup do
    @starter = Infrastructure::MonitoringRunStarter.new
    @asset_ids = [2, 3, 4]
  end

  # ----------------------------------------------------------
  # TEST 1
  # Successful enqueue and Active Job UUID persistence
  # ----------------------------------------------------------

  test "successfully enqueues a job and persists its identity" do
    job = Struct.new(:job_id).new(SecureRandom.uuid)

    with_eligible_assets do
      Infrastructure::ConnectivityBatchJob.stub(:perform_later, job) do
        run = @starter.call

        assert_equal "Queued", run.reload.status
        assert_equal @asset_ids.size, run.total_assets
        assert_equal job.job_id, run.active_job_id
        assert_nil run.completed_at
      end
    end
  end

  # ----------------------------------------------------------
  # TEST 2
  # Enqueue returns nil
  # ----------------------------------------------------------

  test "marks the monitoring run failed when enqueue returns nil" do
    with_eligible_assets do
      Infrastructure::ConnectivityBatchJob.stub(:perform_later, nil) do
        assert_raises(
          Infrastructure::MonitoringRunStarter::EnqueueFailed
        ) do
          @starter.call
        end
      end
    end

    run = InfrastructureMonitoringRun.order(id: :desc).first

    assert_not_nil run
    assert_equal "Failed", run.status
    assert_not_nil run.completed_at
    assert_match(/Job enqueue failed/, run.error_message)
  end

  # ----------------------------------------------------------
  # TEST 3
  # Solid Queue enqueue raises an exception
  # ----------------------------------------------------------

  test "marks the monitoring run failed when enqueue raises" do
    enqueue_error = StandardError.new("Queue unavailable")

    with_eligible_assets do
      Infrastructure::ConnectivityBatchJob.stub(
        :perform_later,
        ->(*) { raise enqueue_error }
      ) do
        assert_raises(
          Infrastructure::MonitoringRunStarter::EnqueueFailed
        ) do
          @starter.call
        end
      end
    end

    run = InfrastructureMonitoringRun.order(id: :desc).first

    assert_not_nil run
    assert_equal "Failed", run.status
    assert_not_nil run.completed_at
    assert_match(/Job enqueue failed/, run.error_message)
  end

  # ----------------------------------------------------------
  # TEST 4
  # Job successfully enqueued, but UUID persistence fails
  #
  # Critical safeguard:
  # The monitoring run must NOT be marked Failed because
  # its background worker may already be executing.
  # ----------------------------------------------------------

  test "does not mark an enqueued run failed when identity persistence fails" do
    job = Struct.new(:job_id).new(SecureRandom.uuid)

    with_eligible_assets do
      Infrastructure::ConnectivityBatchJob.stub(:perform_later, job) do
        original_create = InfrastructureMonitoringRun.method(:create!)

        InfrastructureMonitoringRun.stub(
          :create!,
          ->(**attributes) {
            run = original_create.call(**attributes)

            run.define_singleton_method(:update!) do |**_values|
              raise ActiveRecord::RecordInvalid,
                    "Simulated identity persistence failure"
            end

            run
          }
        ) do
          error = assert_raises(
            Infrastructure::MonitoringRunStarter::JobIdentityPersistenceFailed
          ) do
            @starter.call
          end

          assert_match(
            /could not be persisted/,
            error.message
          )
        end
      end
    end

    run = InfrastructureMonitoringRun.order(id: :desc).first

    assert_not_nil run
    assert_equal "Queued", run.status
    assert_nil run.completed_at
    assert_nil run.active_job_id
  end

  # ----------------------------------------------------------
  # TEST 5
  # No eligible infrastructure assets
  # ----------------------------------------------------------

  test "rejects monitoring when no eligible assets exist" do
    with_asset_ids([]) do
      assert_raises(
        Infrastructure::MonitoringRunStarter::NoAssets
      ) do
        @starter.call
      end
    end
  end

 # ----------------------------------------------------------
  # TEST 6
  # Worker starts before Active Job UUID persistence.
  #
  # The starter must not overwrite the worker's Running
  # status, execution token, or heartbeat.
  # ----------------------------------------------------------

  test "preserves worker ownership when worker starts before identity persistence" do
    job = Struct.new(:job_id).new(SecureRandom.uuid)
    worker_token = SecureRandom.uuid
    worker_started_at = 1.minute.ago

    with_eligible_assets do
      Infrastructure::ConnectivityBatchJob.stub(
        :perform_later,
        ->(run_id, _asset_ids) {
          InfrastructureMonitoringRun
            .where(id: run_id, status: "Queued")
            .update_all(
              status: "Running",
              execution_token: worker_token,
              started_at: worker_started_at,
              heartbeat_at: worker_started_at,
              updated_at: Time.current
            )

          job
        }
      ) do
        run = @starter.call
        run.reload

        assert_equal "Running", run.status
        assert_equal job.job_id, run.active_job_id
        assert_equal worker_token, run.execution_token
        assert_not_nil run.started_at
        assert_not_nil run.heartbeat_at
        assert_nil run.completed_at
      end
    end
  end


  private

  # ----------------------------------------------------------
  # Mock the complete Active Record query:
  #
  # InfrastructureAsset
  #   .where.not(status: "Retired")
  #   .order(:id)
  #   .pluck(:id)
  #
  # No real infrastructure inventory records are required.
  # ----------------------------------------------------------

  def with_eligible_assets(&block)
    with_asset_ids(@asset_ids, &block)
  end

  def with_asset_ids(ids)
    relation = Object.new

    relation.define_singleton_method(:not) do |**_conditions|
      self
    end

    relation.define_singleton_method(:order) do |_column|
      self
    end

    relation.define_singleton_method(:pluck) do |_column|
      ids
    end

    InfrastructureAsset.stub(:where, relation) do
      yield
    end
  end
end
