# frozen_string_literal: true

module Infrastructure
  class MonitoringAnalytics
    PERIODS = { "7" => 7, "30" => 30, "90" => 90 }.freeze
    attr_reader :period, :start_at, :end_at, :daily, :summary

    def initialize(params: {}, now: Time.current)
      @period = PERIODS.key?(params[:period].to_s) ? params[:period].to_s : "30"
      @end_at = now
      @start_at = now - PERIODS.fetch(@period).days
    end

    def call
      days = (start_at.to_date..end_at.to_date).to_a
      @daily = days.index_with do |date|
        { date: date, completed: 0, failed: 0, other: 0,
          reachable: 0, unreachable: 0, unknown: 0,
          assessments: 0, breaches: 0, insufficient: 0, queue_failures: 0 }
      end

      InfrastructureMonitoringRun.where(created_at: start_at...end_at)
        .group("DATE(created_at)", :status).count.each do |(date, status), count|
        row = @daily[date.to_date]
        next unless row
        key = { "Completed" => :completed, "Failed" => :failed }.fetch(status, :other)
        row[key] += count
      end

      InfrastructureConnectivityResult.where(checked_at: start_at...end_at)
        .group("DATE(checked_at)", :icmp_status).count.each do |(date, status), count|
        row = @daily[date.to_date]
        next unless row
        key = { "Reachable" => :reachable, "Unreachable" => :unreachable }.fetch(status, :unknown)
        row[key] += count
      end

      InfrastructureAvailabilityAssessment.where(period_end: start_at...end_at)
        .group("DATE(period_end)", :assessment_status).count.each do |(date, status), count|
        row = @daily[date.to_date]
        next unless row
        row[:assessments] += count
        row[:breaches] += count if status == "BelowThreshold"
        row[:insufficient] += count if status == "InsufficientData"
      end

      SolidQueue::FailedExecution.where(created_at: start_at...end_at)
        .group("DATE(created_at)").count.each do |date, count|
        @daily[date.to_date][:queue_failures] += count if @daily.key?(date.to_date)
      end

      @daily = @daily.values
      completed = @daily.sum { |r| r[:completed] }
      failed = @daily.sum { |r| r[:failed] }
      reachable = @daily.sum { |r| r[:reachable] }
      unreachable = @daily.sum { |r| r[:unreachable] }
      @summary = {
        completed: completed, failed: failed,
        other: @daily.sum { |r| r[:other] },
        execution_success_percentage: percentage(completed, completed + failed),
        reachable_checks: reachable, unreachable_checks: unreachable,
        unknown_checks: @daily.sum { |r| r[:unknown] },
        connectivity_availability_percentage: percentage(reachable, reachable + unreachable),
        assessments: @daily.sum { |r| r[:assessments] },
        breaches: @daily.sum { |r| r[:breaches] },
        insufficient: @daily.sum { |r| r[:insufficient] },
        historical_queue_failures_in_period: @daily.sum { |r| r[:queue_failures] }
      }
      self
    end

    def chart_rows
      daily.map do |row|
        determinate = row[:reachable] + row[:unreachable]
        finished = row[:completed] + row[:failed]
        row.merge(
          execution_success_percentage: percentage(row[:completed], finished),
          connectivity_availability_percentage: percentage(row[:reachable], determinate)
        )
      end
    end

    private

    def percentage(numerator, denominator)
      return nil if denominator.zero?
      (100.0 * numerator / denominator).round(2)
    end
  end
end
