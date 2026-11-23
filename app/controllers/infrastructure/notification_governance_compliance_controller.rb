# frozen_string_literal: true

module Infrastructure
  class NotificationGovernanceComplianceController < ApplicationController
    before_action :require_portal_administrator

    def index
      @report = NotificationGovernanceComplianceReport.new
      @assessment = @report.assessment
      @section_counts = @report.section_counts
    end

    def export
      section = params[:section].to_s
      unless NotificationGovernanceComplianceReport::SECTIONS.include?(section)
        return head :bad_request
      end

      report = NotificationGovernanceComplianceReport.new
      send_data report.csv(section: section),
                type: "text/csv; charset=utf-8",
                disposition: "attachment",
                filename: "herga-governance-#{section}-#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}.csv"
    end
  end
end
