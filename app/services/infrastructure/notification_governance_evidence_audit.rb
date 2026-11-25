# frozen_string_literal: true

require "json"
require "digest"
require "time"

module Infrastructure
  # HERGA Corporate Portal
  #
  # Structured security audit logging for governance
  # evidence generation.
  #
  # Audit records identify the generated evidence without
  # including the evidence contents or signing material.
  #
  # A generated event confirms successful server-side
  # generation, not receipt of the file by the client.
  class NotificationGovernanceEvidenceAudit
    EVENT_NAME = "governance_evidence_export"

    EXPORT_TYPES = %w[
      csv
      evidence_bundle
    ].freeze

    OUTCOMES = %w[
      generated
      rejected
      failed
    ].freeze

    def initialize(
      actor:,
      roles:,
      request_id:,
      logger: Rails.logger,
      clock: -> { Time.current }
    )
      @actor = actor.to_s
      @roles = Array(roles)
        .select { |role| PortalAuthorization.valid_role?(role) }
        .map(&:to_s)
        .uniq
        .sort

      @request_id = request_id.to_s
      @logger = logger
      @clock = clock
    end

    # ==========================================================
    # SUCCESSFUL EVIDENCE GENERATION
    # ==========================================================

    def generated(
      export_type:,
      section: nil,
      data:
    )
      payload = base_payload(
        export_type: export_type,
        section: section,
        outcome: "generated"
      )

      payload[:bytes] = data.bytesize
      payload[:sha256] = Digest::SHA256.hexdigest(data)

      write_event(payload)
    end

    # ==========================================================
    # REJECTED EXPORT REQUEST
    # ==========================================================

    def rejected(
      export_type:,
      section: nil,
      reason:
    )
      payload = base_payload(
        export_type: export_type,
        section: section,
        outcome: "rejected"
      )

      payload[:reason] = reason.to_s

      write_event(payload)
    end

    # ==========================================================
    # FAILED EVIDENCE GENERATION
    # ==========================================================

    def failed(
      export_type:,
      section: nil,
      error:
    )
      payload = base_payload(
        export_type: export_type,
        section: section,
        outcome: "failed"
      )

      # Record the exception class only.
      #
      # Exception messages may contain internal paths,
      # database details or other sensitive information.
      payload[:error_class] = error.class.name

      write_event(payload)
    end

    private

    # ==========================================================
    # COMMON AUDIT EVENT STRUCTURE
    # ==========================================================

    def base_payload(
      export_type:,
      section:,
      outcome:
    )
      export_type = export_type.to_s
      outcome = outcome.to_s

      unless EXPORT_TYPES.include?(export_type)
        raise ArgumentError, "Unsupported evidence export type"
      end

      unless OUTCOMES.include?(outcome)
        raise ArgumentError, "Unsupported evidence audit outcome"
      end

      {
        event: EVENT_NAME,
        timestamp_utc: @clock.call.utc.iso8601(6),
        actor: @actor,
        roles: @roles,
        request_id: @request_id,
        export_type: export_type,
        section: safe_section(section),
        outcome: outcome
      }
    end

    # ==========================================================
    # SECTION VALIDATION
    # ==========================================================

    def safe_section(section)
      return nil if section.nil?

      value = section.to_s

      if NotificationGovernanceComplianceReport::SECTIONS.include?(value)
        value
      else
        "invalid"
      end
    end

    # ==========================================================
    # STRUCTURED SECURITY LOGGING
    # ==========================================================

    def write_event(payload)
      message = JSON.generate(payload)

      case payload.fetch(:outcome)
      when "generated"
        @logger.info(message)

      when "rejected"
        @logger.warn(message)

      when "failed"
        @logger.error(message)
      end

      payload
    end
  end
end