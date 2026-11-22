# frozen_string_literal: true

require "csv"

module Infrastructure
  class AvailabilityController < ApplicationController
    before_action :require_portal_administrator

    PERIODS = { "1" => 1, "7" => 7, "30" => 30 }.freeze
    THRESHOLDS = { "99" => 99.0, "95" => 95.0, "90" => 90.0 }.freeze
    PER_PAGE = 25

    def index
      @period = PERIODS.key?(params[:period].to_s) ? params[:period].to_s : "7"
      @period_days = PERIODS.fetch(@period)
      @period_end = Time.current
      @period_start = @period_end - @period_days.days
      @threshold = THRESHOLDS.key?(params[:threshold].to_s) ? params[:threshold].to_s : "99"
      @threshold_value = THRESHOLDS.fetch(@threshold)
      @risk_filter = %w[all below meets no_data].include?(params[:risk].to_s) ? params[:risk].to_s : "all"

      @environment = InfrastructureAsset::ENVIRONMENTS.include?(params[:environment].to_s) ? params[:environment].to_s : nil
      @asset_type = InfrastructureAsset::ASSET_TYPES.include?(params[:asset_type].to_s) ? params[:asset_type].to_s : nil
      @query = params[:q].to_s.strip.first(100)

      # Retired assets are excluded from operational reporting.
      assets = InfrastructureAsset.where.not(status: "Retired")
      assets = assets.where(environment: @environment) if @environment
      assets = assets.where(asset_type: @asset_type) if @asset_type
      if @query.present?
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
        assets = assets.where("hostname ILIKE :q OR fqdn ILIKE :q OR ip_address ILIKE :q", q: pattern)
      end

      all_assets = assets.select(:id, :hostname, :fqdn, :environment, :asset_type, :status).to_a
      ids = all_assets.map(&:id)
      @stats = {}
      @previous_stats = {}

      if ids.any?
        relation = InfrastructureConnectivityResult.where(
          infrastructure_asset_id: ids, checked_at: @period_start..@period_end
        )
        rows = relation.group(:infrastructure_asset_id).pluck(
          :infrastructure_asset_id,
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(*) FILTER (WHERE icmp_status = 'Reachable')"),
          Arel.sql("COUNT(*) FILTER (WHERE icmp_status = 'Unreachable')"),
          Arel.sql("AVG(icmp_response_ms) FILTER (WHERE icmp_status = 'Reachable' AND icmp_response_ms IS NOT NULL)")
        )

        rows.each do |id, total, reachable, unreachable, average_ms|
          determinate = reachable + unreachable
          @stats[id] = {
            total: total, reachable: reachable, unreachable: unreachable,
            unknown: total - determinate, determinate: determinate,
            availability: determinate.positive? ? (100.0 * reachable / determinate).round(2) : nil,
            average_latency: average_ms&.to_f
          }
        end
      end

      # Compare with the immediately preceding window of equal duration.
      # Use a half-open interval to prevent boundary checks being counted twice.
      previous_start = @period_start - @period_days.days
      previous_rows = if ids.any?
        InfrastructureConnectivityResult
          .where(infrastructure_asset_id: ids)
          .where("checked_at >= ? AND checked_at < ?", previous_start, @period_start)
          .group(:infrastructure_asset_id)
          .pluck(
            :infrastructure_asset_id,
            Arel.sql("COUNT(*) FILTER (WHERE icmp_status = 'Reachable')"),
            Arel.sql("COUNT(*) FILTER (WHERE icmp_status = 'Unreachable')")
          )
      else
        []
      end
      previous_rows.each do |id, reachable, unreachable|
        determinate = reachable + unreachable
        @previous_stats[id] = determinate.positive? ? (100.0 * reachable / determinate).round(2) : nil
      end

      @empty_stats = { total: 0, reachable: 0, unreachable: 0, unknown: 0,
                       determinate: 0, availability: nil, average_latency: nil }.freeze

      # Summary describes all assets matching environment/type/search, before risk filtering.
      @total_scope_assets = all_assets.size
      @assets_with_checks = all_assets.count { |asset| @stats.fetch(asset.id, @empty_stats)[:total].positive? }
      @assets_without_checks = @total_scope_assets - @assets_with_checks
      @total_checks = @stats.values.sum { |stat| stat[:total] }
      @reachable_checks = @stats.values.sum { |stat| stat[:reachable] }
      @unreachable_checks = @stats.values.sum { |stat| stat[:unreachable] }
      @unknown_checks = @stats.values.sum { |stat| stat[:unknown] }
      determinate_total = @reachable_checks + @unreachable_checks
      @overall_availability = determinate_total.positive? ? (100.0 * @reachable_checks / determinate_total).round(2) : nil

      @below_threshold_count = all_assets.count { |asset| risk_for(@stats.fetch(asset.id, @empty_stats)) == "below" }
      @meets_threshold_count = all_assets.count { |asset| risk_for(@stats.fetch(asset.id, @empty_stats)) == "meets" }
      @no_data_count = all_assets.count { |asset| risk_for(@stats.fetch(asset.id, @empty_stats)) == "no_data" }

      @previous_period_start = previous_start
      @previous_period_end = @period_start
      @previous_reachable = previous_rows.sum { |_, reachable, _| reachable }
      @previous_unreachable = previous_rows.sum { |_, _, unreachable| unreachable }
      previous_determinate = @previous_reachable + @previous_unreachable
      @previous_overall_availability = previous_determinate.positive? ?
        (100.0 * @previous_reachable / previous_determinate).round(2) : nil
      @availability_change = if @overall_availability && @previous_overall_availability
        (@overall_availability - @previous_overall_availability).round(2)
      end

      # Reporting alerts only. No incident records or emails are generated.
      @breached_assets = all_assets.select do |asset|
        risk_for(@stats.fetch(asset.id, @empty_stats)) == "below"
      end.sort_by do |asset|
        [@stats.fetch(asset.id, @empty_stats)[:availability], asset.hostname, asset.id]
      end
      @new_breaches = @breached_assets.select do |asset|
        prior = @previous_stats[asset.id]
        prior && prior >= @threshold_value
      end

      @asset_rows = if @risk_filter == "all"
                      all_assets
                    else
                      all_assets.select { |asset| risk_for(@stats.fetch(asset.id, @empty_stats)) == @risk_filter }
                    end

      # Lowest measured availability first, no determinate data last.
      @asset_rows.sort_by! do |asset|
        stat = @stats.fetch(asset.id, @empty_stats)
        [stat[:availability].nil? ? 1 : 0, stat[:availability] || 0.0,
         -stat[:unreachable], asset.hostname, asset.id]
      end

      @total_assets = @asset_rows.size
      @total_pages = [(@total_assets.to_f / PER_PAGE).ceil, 1].max
      @page = [[params[:page].to_i, 1].max, @total_pages].min
      @display_assets = @asset_rows.slice((@page - 1) * PER_PAGE, PER_PAGE) || []

      respond_to do |format|
        format.html
        format.csv do
          send_data export_csv,
                    filename: "herga-availability-#{@period_days}d-#{Time.current.utc.strftime('%Y%m%d-%H%M%S')}.csv",
                    type: "text/csv; charset=utf-8",
                    disposition: "attachment"
        end
      end
    end

    private

    def risk_for(stat)
      return "no_data" if stat[:availability].nil?

      stat[:availability] < @threshold_value ? "below" : "meets"
    end

    # Prevent spreadsheet formula execution when a user opens exported CSV.
    def csv_safe(value)
      text = value.to_s
      text.match?(/\A[\s]*[=+@-]/) ? "'#{text}" : text
    end

    def export_csv
      CSV.generate(headers: true) do |csv|
        csv << ["Asset ID", "Hostname", "FQDN", "Environment", "Asset Type", "Lifecycle Status",
                "Period Start (UTC)", "Period End (UTC)", "Threshold (%)", "Threshold Result",
                "Availability (%)", "Total Checks", "Reachable", "Unreachable", "Unknown",
                "Determinate Checks", "Average ICMP Latency (ms)",
                "Previous Period Availability (%)", "Availability Change (pp)", "New Threshold Breach"]

        # CSV exports the full filtered ranking, not only the visible page.
        @asset_rows.each do |asset|
          stat = @stats.fetch(asset.id, @empty_stats)
          csv << [asset.id, csv_safe(asset.hostname), csv_safe(asset.fqdn),
                  csv_safe(asset.environment), csv_safe(asset.asset_type), csv_safe(asset.status),
                  @period_start.utc.iso8601, @period_end.utc.iso8601, @threshold,
                  risk_for(stat), stat[:availability], stat[:total], stat[:reachable],
                  stat[:unreachable], stat[:unknown], stat[:determinate],
                  stat[:average_latency]&.round(2),
                  @previous_stats[asset.id],
                  (stat[:availability] && @previous_stats[asset.id] ?
                    (stat[:availability] - @previous_stats[asset.id]).round(2) : nil),
                  @new_breaches.any? { |breach| breach.id == asset.id } ? "Yes" : "No"]
        end
      end
    end
  end
end
