# frozen_string_literal: true

module Infrastructure
  # HERGA Corporate Portal
  #
  # Governance compliance reporting and evidence exports.
  #
  # All permissions are resolved through live Active
  # Directory-backed RBAC.
  #
  # Evidence exports include structured accountability
  # logging and explicit HTTP cache protection.
  class NotificationGovernanceComplianceController < ApplicationController

    # ==========================================================
    # RESPONSE CONFIDENTIALITY
    # ==========================================================

    prepend_before_action :prevent_evidence_caching,
                          only: %i[
                            export
                            evidence_bundle
                          ]

    # ==========================================================
    # GOVERNANCE AUTHORISATION
    # ==========================================================

    before_action -> {
      require_portal_permission(:governance_read)
    }, only: :index

    before_action -> {
      require_portal_permission(:governance_evidence_read)
    }, except: :index

    # ==========================================================
    # GOVERNANCE COMPLIANCE DASHBOARD
    # ==========================================================

    def index
      @report = NotificationGovernanceComplianceReport.new
      @assessment = @report.assessment
      @section_counts = @report.section_counts
    end

    # ==========================================================
    # INDIVIDUAL CSV EVIDENCE EXPORT
    # ==========================================================

    def export
      section = params[:section].to_s

      unless NotificationGovernanceComplianceReport::SECTIONS.include?(section)

        evidence_audit.rejected(
          export_type: "csv",
          section: section,
          reason: "unsupported_export_section"
        )

        return head :bad_request
      end

      report = NotificationGovernanceComplianceReport.new

      data = report.csv(section: section)

      evidence_audit.generated(
        export_type: "csv",
        section: section,
        data: data
      )

      send_data(
        data,
        type: "text/csv; charset=utf-8",
        disposition: "attachment",
        filename: "herga-governance-#{section}-" \
                  "#{evidence_timestamp}.csv"
      )

    rescue StandardError => error

      evidence_audit.failed(
        export_type: "csv",
        section: section,
        error: error
      )

      raise
    end

    # ==========================================================
    # COMPLETE GOVERNANCE EVIDENCE ARCHIVE
    # ==========================================================

    def evidence_bundle
      data = NotificationGovernanceEvidenceBundle.new.build

      evidence_audit.generated(
        export_type: "evidence_bundle",
        data: data
      )

      send_data(
        data,
        type: "application/gzip",
        disposition: "attachment",
        filename: "herga-governance-evidence-" \
                  "#{evidence_timestamp}.tar.gz"
      )

    rescue NotificationGovernanceEvidenceBundle::BundleTooLarge => error

      evidence_audit.failed(
        export_type: "evidence_bundle",
        error: error
      )

      render(
        plain: "Governance evidence exceeds the maximum bundle size.",
        status: :unprocessable_entity
      )

    rescue StandardError => error

      evidence_audit.failed(
        export_type: "evidence_bundle",
        error: error
      )

      raise
    end

    private

    # ==========================================================
    # EVIDENCE CACHE PROTECTION
    # ==========================================================

    def prevent_evidence_caching
      no_store

      response.headers["Cache-Control"] =
        "no-store, no-cache, must-revalidate, private, max-age=0"

      response.headers["Pragma"] = "no-cache"

      response.headers["Expires"] =
        "Thu, 01 Jan 1970 00:00:00 GMT"

      response.headers["X-Content-Type-Options"] = "nosniff"
    end

    # ==========================================================
    # EVIDENCE AUDIT CONTEXT
    # ==========================================================

    def evidence_audit
      @evidence_audit ||= NotificationGovernanceEvidenceAudit.new(
        actor: current_user.username,
        roles: current_portal_roles,
        request_id: request.request_id
      )
    end

    # ==========================================================
    # EVIDENCE FILENAME TIMESTAMP
    # ==========================================================

    def evidence_timestamp
      Time.current.utc.strftime("%Y%m%dT%H%M%SZ")
    end
  end
end