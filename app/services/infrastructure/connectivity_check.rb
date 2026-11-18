# frozen_string_literal: true

require "resolv"
require "open3"
require "timeout"
require "ipaddr"

module Infrastructure
  class ConnectivityCheck
    DNS_TIMEOUT = 3
    PING_TIMEOUT = 5

    def initialize(asset, monitoring_run: nil)
      @asset = asset
      @monitoring_run = monitoring_run
    end

    def call
      hostname = @asset.fqdn.presence || @asset.hostname

      dns_status = "Failed"
      resolved_ip = nil
      icmp_status = "Unknown"
      response_ms = nil
      errors = []

      # --------------------------------------------------------
      # DNS Resolution
      # --------------------------------------------------------

      begin
        Timeout.timeout(DNS_TIMEOUT) do
          addresses = Resolv.getaddresses(hostname)

          resolved_ip = addresses.find do |address|
            IPAddr.new(address).ipv4?
          end

          dns_status = resolved_ip.present? ? "Resolved" : "Failed"
        end

      rescue Timeout::Error
        errors << "DNS lookup timed out"

      rescue Resolv::ResolvError, SocketError => e
        errors << "DNS lookup failed: #{e.class}"
      end

      # --------------------------------------------------------
      # ICMP Reachability
      # --------------------------------------------------------

      if resolved_ip.present?
        begin
          output, error_output, status = Timeout.timeout(PING_TIMEOUT) do
            Open3.capture3(
              "ping",
              "-n",
              "-c", "1",
              "-W", "2",
              resolved_ip
            )
          end

          if status.success?
            icmp_status = "Reachable"

            match = output.match(/time[=<]([\d.]+)\s*ms/i)
            response_ms = match[1].to_f if match
          else
            icmp_status = "Unreachable"

            if error_output.present?
              errors << error_output.strip
            end
          end

        rescue Timeout::Error
          icmp_status = "Unknown"
          errors << "ICMP check timed out"

        rescue Errno::ENOENT
          icmp_status = "Unknown"
          errors << "Ping executable not installed"

        rescue SystemCallError => e
          icmp_status = "Unknown"
          errors << "ICMP execution failed: #{e.class}"
        end
      else
        errors << "No IPv4 address resolved"
      end

      # --------------------------------------------------------
      # Save Latest Status and Historical Result Atomically
      # --------------------------------------------------------

      checked_at = Time.current
      diagnostic = errors.join("; ").presence

      InfrastructureAsset.transaction do
        @asset.update!(
          dns_status: dns_status,
          resolved_ip_address: resolved_ip,
          icmp_status: icmp_status,
          icmp_response_ms: response_ms,
          last_connectivity_check_at: checked_at,
          connectivity_error: diagnostic
        )

        connectivity_result = InfrastructureConnectivityResult.create!(
          infrastructure_asset: @asset,
          infrastructure_monitoring_run: @monitoring_run,
          dns_status: dns_status,
          resolved_ip_address: resolved_ip,
          icmp_status: icmp_status,
          icmp_response_ms: response_ms,
          connectivity_error: diagnostic,
          checked_at: checked_at
        )

        Infrastructure::IncidentDetector.new(
          @asset, connectivity_result: connectivity_result
        ).call
      end

      Rails.logger.info(
        "[Infrastructure] Connectivity recorded: " \
        "asset=#{@asset.hostname}, " \
        "dns=#{dns_status}, " \
        "icmp=#{icmp_status}, " \
        "latency_ms=#{response_ms || 'N/A'}"
      )

      @asset
    end
  end
end
