# frozen_string_literal: true

module Infrastructure
  class NotificationGovernanceComplianceController < ApplicationController
    before_action -> { require_portal_permission(:governance_read) },
                  only: :index

    before_action -> { require_portal_permission(:governance_evidence_read) },
                  except: :index

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

    # Download a read-only CSV archive with a checksum manifest.
    def evidence_bundle
      data = NotificationGovernanceEvidenceBundle.new.build

      send_data data,
                type: "application/gzip",
                disposition: "attachment",
                filename: "herga-governance-evidence-#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}.tar.gz"
    rescue NotificationGovernanceEvidenceBundle::BundleTooLarge
      render plain: "Governance evidence exceeds the maximum bundle size.",
             status: :unprocessable_entity
    end
  end
end
