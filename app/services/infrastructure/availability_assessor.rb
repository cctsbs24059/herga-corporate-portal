# frozen_string_literal: true

module Infrastructure
  class AvailabilityAssessor
    DEFAULT_THRESHOLD = 99.0
    DEFAULT_PERIOD_HOURS = 24

    def initialize(as_of: Time.current, period_hours: DEFAULT_PERIOD_HOURS,
                   threshold: DEFAULT_THRESHOLD)
      @period_end = as_of.change(min: 0, sec: 0, usec: 0)
      @period_hours = Integer(period_hours)
      @threshold = BigDecimal(threshold.to_s)
      raise ArgumentError, "period_hours must be positive" unless @period_hours.positive?
      raise ArgumentError, "threshold must be between 0 and 100" unless @threshold.between?(0, 100)
    end

    def call
      period_start = @period_end - @period_hours.hours
      assets = InfrastructureAsset.where(status: "Active").order(:id)
      # Inclusive lower bound, exclusive upper bound: a check is counted once per window.
      counts = InfrastructureConnectivityResult
        .where(checked_at: period_start...@period_end)
        .where(infrastructure_asset_id: assets.select(:id))
        .group(:infrastructure_asset_id, :icmp_status).count

      now = Time.current
      rows = assets.map do |asset|
        reachable = counts.fetch([asset.id, "Reachable"], 0)
        unreachable = counts.fetch([asset.id, "Unreachable"], 0)
        determinate = reachable + unreachable
        total = counts.select { |(id, _), _| id == asset.id }.values.sum
        unknown = total - determinate
        percentage = determinate.positive? ? (BigDecimal(reachable.to_s) * 100 / determinate).round(2) : nil
        status = if percentage.nil?
                   "InsufficientData"
                 elsif percentage < @threshold
                   "BelowThreshold"
                 else
                   "MeetsThreshold"
                 end

        {
          infrastructure_asset_id: asset.id,
          period_start: period_start,
          period_end: @period_end,
          total_checks: total,
          reachable_checks: reachable,
          unreachable_checks: unreachable,
          unknown_checks: unknown,
          availability_percentage: percentage,
          threshold_percentage: @threshold,
          assessment_status: status,
          created_at: now,
          updated_at: now
        }
      end

      # Re-running an hourly window updates the same assessment, never creates duplicates.
      InfrastructureAvailabilityAssessment.upsert_all(
        rows,
        unique_by: :index_infra_availability_assessments_unique_period,
        update_only: %i[total_checks reachable_checks unreachable_checks unknown_checks
                        availability_percentage threshold_percentage assessment_status]
      ) if rows.any?

      { assets: rows.size, breaches: rows.count { |row| row[:assessment_status] == "BelowThreshold" },
        insufficient_data: rows.count { |row| row[:assessment_status] == "InsufficientData" },
        period_start: period_start, period_end: @period_end }
    end
  end
end
