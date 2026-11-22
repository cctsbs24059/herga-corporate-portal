# frozen_string_literal: true

require "csv"

module Infrastructure
  class AnalyticsController < ApplicationController
    before_action :require_portal_administrator

    def index
      @analytics = Infrastructure::MonitoringAnalytics.new(params: params).call

      respond_to do |format|
        format.html
        format.csv do
          send_data csv_export,
                    filename: "herga-monitoring-analytics-#{@analytics.period}d-#{Time.current.utc.strftime('%Y%m%d-%H%M%S')}.csv",
                    type: "text/csv; charset=utf-8",
                    disposition: "attachment"
        end
      end
    end

    private

    def csv_export
      CSV.generate(headers: true) do |csv|
        csv << ["Date (UTC)", "Completed Runs", "Failed Runs", "Other Runs",
                "Execution Success (%)", "Reachable Checks", "Unreachable Checks",
                "Unknown Checks", "Connectivity Availability (%)", "Assessments",
                "Threshold Breaches", "Insufficient Data", "Historical Queue Failures"]
        @analytics.chart_rows.each do |row|
          csv << [row[:date].iso8601, row[:completed], row[:failed], row[:other],
                  row[:execution_success_percentage], row[:reachable], row[:unreachable],
                  row[:unknown], row[:connectivity_availability_percentage], row[:assessments],
                  row[:breaches], row[:insufficient], row[:queue_failures]]
        end
      end
    end
  end
end
