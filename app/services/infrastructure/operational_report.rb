# frozen_string_literal: true

module Infrastructure
  class OperationalReport
    PERIODS = { "1" => 1, "7" => 7, "30" => 30, "90" => 90 }.freeze
    PER_PAGE = 25
    SECTIONS = %w[runs assessments alerts failures].freeze

    attr_reader :period, :section, :status, :page, :start_at, :end_at,
                :total_rows, :total_pages, :rows, :summary

    def initialize(params:, now: Time.current)
      @period = PERIODS.key?(params[:period].to_s) ? params[:period].to_s : "7"
      @section = SECTIONS.include?(params[:section].to_s) ? params[:section].to_s : "runs"
      @status = params[:status].to_s.strip.first(40)
      @page = [params[:page].to_i, 1].max
      @end_at = now
      @start_at = now - PERIODS.fetch(@period).days
    end

    def call
      @summary = {
        runs: InfrastructureMonitoringRun.where(created_at: start_at...end_at).count,
        completed_runs: InfrastructureMonitoringRun.where(created_at: start_at...end_at, status: "Completed").count,
        failed_runs: InfrastructureMonitoringRun.where(created_at: start_at...end_at, status: "Failed").count,
        assessments: InfrastructureAvailabilityAssessment.where(period_end: start_at...end_at).count,
        breaches: InfrastructureAvailabilityAssessment.where(period_end: start_at...end_at, assessment_status: "BelowThreshold").count,
        alerts: InfrastructureAvailabilityAlert.where(created_at: start_at...end_at).count,
        queue_failures: SolidQueue::FailedExecution.where(created_at: start_at...end_at).count
      }
      @total_rows = relation.count
      @total_pages = [(@total_rows.to_f / PER_PAGE).ceil, 1].max
      @page = [@page, @total_pages].min
      @rows = relation.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
      self
    end

    def export_rows
      relation.find_each(batch_size: 500)
    end

    def csv_headers
      case section
      when "runs" then ["ID", "Status", "Started (UTC)", "Completed (UTC)", "Total Assets", "Processed", "Reachable", "Unreachable", "Unknown", "Failed Checks", "Error"]
      when "assessments" then ["ID", "Asset ID", "Hostname", "Status", "Period Start (UTC)", "Period End (UTC)", "Availability (%)", "Threshold (%)", "Total Checks", "Reachable", "Unreachable", "Unknown"]
      when "alerts" then ["ID", "Asset ID", "Hostname", "Status", "First Detected (UTC)", "Last Observed (UTC)", "Acknowledged (UTC)", "Cleared (UTC)", "Availability (%)", "Threshold (%)"]
      else ["ID", "Job ID", "Job Class", "Failed (UTC)", "Error"]
      end
    end

    def csv_values(record)
      case section
      when "runs"
        [record.id, record.status, timestamp(record.started_at), timestamp(record.completed_at), record.total_assets, record.processed_assets, record.reachable_assets, record.unreachable_assets, record.unknown_assets, record.failed_checks, record.error_message]
      when "assessments"
        [record.id, record.infrastructure_asset_id, record.infrastructure_asset&.hostname, record.assessment_status, timestamp(record.period_start), timestamp(record.period_end), record.availability_percentage, record.threshold_percentage, record.total_checks, record.reachable_checks, record.unreachable_checks, record.unknown_checks]
      when "alerts"
        [record.id, record.infrastructure_asset_id, record.infrastructure_asset&.hostname, record.status, timestamp(record.first_detected_at), timestamp(record.last_observed_at), timestamp(record.acknowledged_at), timestamp(record.cleared_at), record.last_availability_percentage, record.threshold_percentage]
      else
        [record.id, record.job_id, record.job&.class_name, timestamp(record.created_at), record.error.to_s.truncate(1000)]
      end
    end

    private

    def relation
      @relation ||= begin
        scope = case section
                when "runs"
                  InfrastructureMonitoringRun.where(created_at: start_at...end_at)
                when "assessments"
                  InfrastructureAvailabilityAssessment.includes(:infrastructure_asset).where(period_end: start_at...end_at)
                when "alerts"
                  InfrastructureAvailabilityAlert.includes(:infrastructure_asset).where(created_at: start_at...end_at)
                else
                  SolidQueue::FailedExecution.includes(:job).where(created_at: start_at...end_at)
                end
        allowed = case section
                  when "runs" then %w[Queued Running Completed Failed]
                  when "assessments" then InfrastructureAvailabilityAssessment::STATUSES
                  when "alerts" then %w[Active Acknowledged Cleared]
                  else []
                  end
        scope = scope.where((section == "assessments" ? :assessment_status : :status) => status) if allowed.include?(status)
        scope.order(created_at: :desc, id: :desc)
      end
    end

    def timestamp(value)
      value&.utc&.iso8601
    end
  end
end
