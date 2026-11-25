# frozen_string_literal: true

class InfrastructureAssetsController < ApplicationController
  before_action -> { require_portal_permission(:infrastructure_read) },
                only: %i[index show history]

  before_action -> { require_portal_permission(:infrastructure_manage) },
                except: %i[index show history]

  before_action :set_asset, only: %i[
    show history edit update retire check_connectivity
  ]

  PER_PAGE = 25

  def index
    # Infrastructure statistics
    @total_assets = InfrastructureAsset.count
    @ad_assets = InfrastructureAsset.directory_assets.count
    @manual_assets = InfrastructureAsset.manual_assets.count
    @retired_assets = InfrastructureAsset.where(status: "Retired").count

    # Operating system breakdown
    @os_breakdown = {
      "Windows Server 2019" => 0,
      "Windows Server 2022" => 0,
      "Windows Server 2025" => 0,
      "Other / Unknown" => 0
    }

    InfrastructureAsset.group(:operating_system).count.each do |os, count|
      category =
        case os.to_s
        when /Windows Server 2019/i then "Windows Server 2019"
        when /Windows Server 2022/i then "Windows Server 2022"
        when /Windows Server 2025/i then "Windows Server 2025"
        else "Other / Unknown"
        end

      @os_breakdown[category] += count
    end

    @asset_type_breakdown = InfrastructureAsset
                            .group(:asset_type)
                            .count
                            .sort_by { |type, _count| type.to_s }

    @last_ad_sync = InfrastructureAsset.directory_assets
                                       .maximum(:last_ad_sync_at)

    # Connectivity statistics
    @reachable_assets = InfrastructureAsset
                        .where(icmp_status: "Reachable").count

    @unreachable_assets = InfrastructureAsset
                          .where(icmp_status: "Unreachable").count

    @unknown_assets = InfrastructureAsset
                      .where(icmp_status: "Unknown").count

    @not_checked_assets = InfrastructureAsset
                          .where(last_connectivity_check_at: nil).count

    @last_connectivity_check = InfrastructureAsset
                               .maximum(:last_connectivity_check_at)

    # Monitoring history and current run
    @scheduled_monitoring_enabled =
      ENV.fetch("HERGA_CONNECTIVITY_MONITORING_ENABLED", "false") == "true"
    @monitoring_interval_minutes = 15

    @active_monitoring_run = InfrastructureMonitoringRun.active
                                                        .recent
                                                        .first
    @last_completed_monitoring_run = InfrastructureMonitoringRun
                                     .where(status: "Completed")
                                     .recent
                                     .first

    @recent_monitoring_runs = InfrastructureMonitoringRun
                              .recent
                              .limit(5)

    @historical_check_count = InfrastructureConnectivityResult.count

    # Persistent incident statistics, including acknowledged incidents.
    @incident_total = InfrastructureIncident.count
    @open_incident_count = InfrastructureIncident.open_incidents.count
    @acknowledged_incident_count = InfrastructureIncident.where(status: "Acknowledged").count
    @resolved_incident_count = InfrastructureIncident.resolved.count
    @unresolved_incident_count = InfrastructureIncident.unresolved.count
    @critical_incident_count = InfrastructureIncident.unresolved.where(severity: "Critical").count
    @recent_incidents = InfrastructureIncident
                        .includes(:infrastructure_asset)
                        .recent.limit(10)
    @open_incident_asset_ids = InfrastructureIncident.unresolved
                               .distinct.pluck(:infrastructure_asset_id)
    @unresolved_incidents_by_asset_id = InfrastructureIncident.unresolved
      .order(last_observed_at: :desc, id: :desc)
      .to_a.group_by(&:infrastructure_asset_id)

    # Search and filtering
    @query = params[:q].to_s.strip.first(100)
    @asset_type = params[:asset_type].to_s
    @status = params[:status].to_s

    assets = InfrastructureAsset.all

    if @query.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"

      assets = assets.where(
        "hostname ILIKE :q OR fqdn ILIKE :q OR ip_address ILIKE :q OR description ILIKE :q",
        q: pattern
      )
    end

    if InfrastructureAsset::ASSET_TYPES.include?(@asset_type)
      assets = assets.where(asset_type: @asset_type)
    end

    if InfrastructureAsset::STATUSES.include?(@status)
      assets = assets.where(status: @status)
    end

    @total_count = assets.count
    @total_pages = [(@total_count.to_f / PER_PAGE).ceil, 1].max
    @page = [[params[:page].to_i, 1].max, @total_pages].min

    @assets = assets.ordered
                    .limit(PER_PAGE)
                    .offset((@page - 1) * PER_PAGE)

    # Health summary and per-asset status. Load only the 10 newest checks
    # per asset using PostgreSQL window functions (no N+1 queries).
    monitored_assets = InfrastructureAsset.select(:id, :status).to_a
    asset_ids = monitored_assets.map(&:id)
    @health_by_asset_id = {}
    @health_counts = Hash.new(0)
    @availability_by_asset_id = {}

    if asset_ids.any?
      ranked_checks = InfrastructureConnectivityResult
        .select("infrastructure_connectivity_results.*, ROW_NUMBER() OVER (PARTITION BY infrastructure_asset_id ORDER BY checked_at DESC, id DESC) AS health_row_number")
        .where(infrastructure_asset_id: asset_ids)
      recent_checks = InfrastructureConnectivityResult
        .from("(#{ranked_checks.to_sql}) infrastructure_connectivity_results")
        .where("health_row_number <= ?", Infrastructure::HealthEvaluator::HISTORY_LIMIT)
        .to_a
        .group_by(&:infrastructure_asset_id)

      now = Time.current
      monitored_assets.each do |asset|
        health = Infrastructure::HealthEvaluator.new(asset, now: now, checks: recent_checks.fetch(asset.id, [])).call
        @health_by_asset_id[asset.id] = health
        @health_counts[health.status] += 1
      end

      # Percentage of successful recorded ICMP checks, not elapsed-time uptime.
      counts = InfrastructureConnectivityResult
        .where(infrastructure_asset_id: asset_ids)
        .group(:infrastructure_asset_id, :icmp_status).count
      totals = Hash.new(0)
      successful = Hash.new(0)
      counts.each do |(id, status), count|
        totals[id] += count
        successful[id] += count if status == "Reachable"
      end
      totals.each do |id, total|
        @availability_by_asset_id[id] = (100.0 * successful[id] / total).round(1)
      end
    end
  end

  def show
    @recent_connectivity_results = InfrastructureConnectivityResult
                                   .where(infrastructure_asset_id: @asset.id)
                                   .recent
                                   .limit(10)
    @asset_unresolved_incidents = InfrastructureIncident.unresolved
      .where(infrastructure_asset_id: @asset.id)
      .recent
    @asset_recent_incidents = InfrastructureIncident
      .where(infrastructure_asset_id: @asset.id)
      .includes(:assigned_to)
      .recent
      .limit(10)
  end

  # Phase 2D.8.2.1 - Time-filtered per-asset monitoring history.
  def history
    @period_days = [1, 7, 30].include?(params[:period].to_i) ? params[:period].to_i : 7
    @period_end = Time.current
    @period_start = @period_end - @period_days.days

    results = InfrastructureConnectivityResult
      .where(infrastructure_asset_id: @asset.id)
      .where(checked_at: @period_start..@period_end)

    @total_checks = results.count
    @reachable_checks = results.where(icmp_status: "Reachable").count
    @unreachable_checks = results.where(icmp_status: "Unreachable").count
    @unknown_checks = @total_checks - @reachable_checks - @unreachable_checks
    @determinate_checks = @reachable_checks + @unreachable_checks
    @availability_percentage = if @determinate_checks.positive?
      (100.0 * @reachable_checks / @determinate_checks).round(2)
    end

    latency_results = results.where(icmp_status: "Reachable").where.not(icmp_response_ms: nil)
    @average_latency = latency_results.average(:icmp_response_ms)&.to_f
    @minimum_latency = latency_results.minimum(:icmp_response_ms)
    @maximum_latency = latency_results.maximum(:icmp_response_ms)

    @chart_results = results.order(checked_at: :desc, id: :desc).limit(24).to_a.reverse
    @chart_maximum_latency = [
      @chart_results.filter_map { |result| result.icmp_response_ms if result.icmp_status == "Reachable" }.max.to_f,
      1.0
    ].max

    @per_page = 25
    @total_pages = [(@total_checks.to_f / @per_page).ceil, 1].max
    @page = [[params[:page].to_i, 1].max, @total_pages].min
    @connectivity_results = results.order(checked_at: :desc, id: :desc)
      .limit(@per_page).offset((@page - 1) * @per_page)
  end

  def new
    @asset = InfrastructureAsset.new
  end

  def create
    @asset = InfrastructureAsset.new(asset_params)
    @asset.source = "Manual"

    if @asset.save
      redirect_to infrastructure_asset_path(@asset),
                  notice: "Infrastructure asset registered successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    return if manual_asset?
  end

  def update
    return unless manual_asset?

    if @asset.update(asset_params)
      redirect_to infrastructure_asset_path(@asset),
                  notice: "Infrastructure asset updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def retire
    return unless manual_asset?

    @asset.with_lock do
      @asset.update!(status: "Retired")
      InfrastructureIncident.unresolved
        .where(infrastructure_asset_id: @asset.id)
        .find_each do |incident|
          incident.update!(
            status: "Resolved",
            resolved_at: Time.current,
            resolution_reason: "Asset retired",
            suppress_until_recovery: false
          )
          incident.infrastructure_incident_events.create!(
            event_type: "Retired",
            user: current_user,
            details: "Incident resolved because asset was retired by #{current_user.username}"
          )
        end
    end

    redirect_to infrastructure_assets_path,
                notice: "Infrastructure asset retired successfully."
  end

  # Active Directory synchronization
  def sync_active_directory
    result = ActiveDirectory::ServerSync.new.call

    message = [
      "AD discovery completed.",
      "Discovered: #{result.discovered}.",
      "Created: #{result.created}.",
      "Updated: #{result.updated}.",
      "Skipped: #{result.skipped}."
    ].join(" ")

    if result.conflicts.any?
      Rails.logger.warn(
        "Infrastructure synchronization conflicts: " \
        "#{result.conflicts.join('; ')}"
      )

      redirect_to infrastructure_assets_path, alert: message
    else
      redirect_to infrastructure_assets_path, notice: message
    end

  rescue ActiveDirectory::ServerSync::SyncError => e
    Rails.logger.error(
      "Infrastructure synchronization failed: #{e.class}: #{e.message}"
    )

    redirect_to infrastructure_assets_path,
                alert: "Active Directory synchronization failed. No changes were applied."
  end

  # Individual connectivity check
  def check_connectivity
    Infrastructure::ConnectivityCheck.new(@asset).call

    @asset.reload

    Rails.logger.info(
      "Infrastructure connectivity check completed: " \
      "Asset=#{@asset.hostname}, " \
      "DNS=#{@asset.dns_status}, " \
      "ICMP=#{@asset.icmp_status}, " \
      "IP=#{@asset.resolved_ip_address}"
    )

    redirect_to infrastructure_asset_path(@asset),
                notice: "Connectivity check completed for #{@asset.hostname}."

  rescue StandardError => e
    Rails.logger.error(
      "Infrastructure connectivity check failed: " \
      "AssetID=#{@asset&.id}, " \
      "Error=#{e.class}: #{e.message}"
    )

    redirect_to infrastructure_asset_path(@asset),
                alert: "Connectivity check could not be completed."
  end

  # Manual and scheduled checks use the same guarded run starter.
  def check_all_connectivity
    run = Infrastructure::MonitoringRunStarter.new.call

    redirect_to infrastructure_assets_path,
                notice: "Monitoring run ##{run.id} queued for #{run.total_assets} infrastructure assets."
  rescue Infrastructure::MonitoringRunStarter::AlreadyRunning
    redirect_to infrastructure_assets_path,
                alert: "A monitoring run is already queued or running. Please wait for it to finish."
  rescue Infrastructure::MonitoringRunStarter::NoAssets
    redirect_to infrastructure_assets_path,
                alert: "No eligible infrastructure assets to check."
  rescue Infrastructure::MonitoringRunStarter::EnqueueFailed => e
    Rails.logger.error("[Infrastructure] Unable to enqueue monitoring: #{e.message}")
    redirect_to infrastructure_assets_path,
                alert: "Unable to queue infrastructure connectivity checks."
  end

  private

  def set_asset
    @asset = InfrastructureAsset.find(params[:id])
  end

  def manual_asset?
    return true if @asset.manually_registered?

    redirect_to infrastructure_asset_path(@asset),
                alert: "Active Directory assets cannot be edited manually."

    false
  end

  def asset_params
    params.require(:infrastructure_asset).permit(
      :hostname,
      :fqdn,
      :ip_address,
      :asset_type,
      :operating_system,
      :operating_system_version,
      :environment,
      :location,
      :business_function,
      :status,
      :description,
      :notes
    )
  end
end
