
# frozen_string_literal: true

# ============================================================
# HERGA CORPORATE PORTAL
#
# Phase 2D.8.4.3.9
# Notification Retention & Audit Data Lifecycle Management
#
# Read-only assessment of notification retention eligibility.
#
# IMPORTANT:
# - No records are deleted.
# - No records are archived.
# - No notification statuses are modified.
# - Unknown outcomes remain protected.
# - Retention periods are provisional until approved.
# ============================================================

module Infrastructure
  class NotificationRetentionAssessment

    DEFAULT_DAYS = 365
    MIN_DAYS = 30
    MAX_DAYS = 3650

    PROTECTED_STATUSES = %w[
      Pending
      Sending
      Unknown
    ].freeze

    def initialize(now: Time.current, retention_days: nil)
      @now = now

      @retention_days = resolve_days(
        retention_days || ENV["HERGA_NOTIFICATION_RETENTION_DAYS"]
      )
    end

    def call

      # ------------------------------------------------------
      # 1. RETENTION CUTOFF
      # ------------------------------------------------------

      cutoff = @now - @retention_days.days

      # ------------------------------------------------------
      # 2. BASE DATASETS
      # ------------------------------------------------------

      notifications = InfrastructureNotification.all

      attempts = InfrastructureNotificationAttempt.all

      # ------------------------------------------------------
      # 3. ACCEPTED NOTIFICATIONS
      # ------------------------------------------------------
      #
      # Accepted means Microsoft Graph accepted submission.
      # It does not confirm delivery to the recipient.
      #
      # ------------------------------------------------------

      accepted = notifications.where(
        status: "Accepted"
      )

      # ------------------------------------------------------
      # 4. RETENTION CANDIDATES
      # ------------------------------------------------------
      #
      # Explicitly qualify created_at to prevent PostgreSQL
      # ambiguity when joining notification attempts.
      #
      # ------------------------------------------------------

      candidates = accepted.where(
        "infrastructure_notifications.created_at < ?",
        cutoff
      )

      # ------------------------------------------------------
      # 5. PROTECTED NOTIFICATIONS
      # ------------------------------------------------------
      #
      # Pending and Sending notifications may still require
      # processing.
      #
      # Unknown outcomes require investigation and must not
      # be interpreted as confirmed delivery failures.
      #
      # ------------------------------------------------------

      protected = notifications.where(
        status: PROTECTED_STATUSES
      )

      # ------------------------------------------------------
      # 6. CANDIDATES WITH DELIVERY AUDIT HISTORY
      # ------------------------------------------------------
      #
      # Count distinct notifications to prevent multiple
      # delivery attempts inflating the candidate count.
      #
      # This is reporting only.
      #
      # ------------------------------------------------------

      candidates_with_attempts =
        candidates
          .joins(:infrastructure_notification_attempts)
          .distinct
          .count(:id)

      # ------------------------------------------------------
      # 7. AGED DELIVERY ATTEMPTS
      # ------------------------------------------------------
      #
      # Assess attempt age using attempted_at rather than
      # the parent notification's created_at.
      #
      # ------------------------------------------------------

      aged_attempts = attempts.where(
        "infrastructure_notification_attempts.attempted_at < ?",
        cutoff
      )

      # ------------------------------------------------------
      # 8. ASSESSMENT RESULTS
      # ------------------------------------------------------

      {
        assessed_at: @now,

        retention_days: @retention_days,

        cutoff_at: cutoff,

        total_notifications: notifications.count,

        accepted_notifications: accepted.count,

        candidate_notifications: candidates.count,

        candidate_with_attempts: candidates_with_attempts,

        protected_notifications: protected.count,

        protected_by_status: protected.group(:status).count,

        total_attempts: attempts.count,

        aged_attempts: aged_attempts.count,

        # Deletion is deliberately disabled.
        eligible_for_deletion: false,

        # Assessment must remain read-only.
        read_only: true
      }

    end

    private

    # --------------------------------------------------------
    # RETENTION CONFIGURATION VALIDATION
    # --------------------------------------------------------
    #
    # Environment variable:
    #
    # HERGA_NOTIFICATION_RETENTION_DAYS
    #
    # Default: 365 days
    # Minimum: 30 days
    # Maximum: 3650 days
    #
    # Invalid values fall back to the default.
    #
    # --------------------------------------------------------

    def resolve_days(value)

      days = Integer(value || DEFAULT_DAYS)

      if days.between?(MIN_DAYS, MAX_DAYS)
        days
      else
        DEFAULT_DAYS
      end

    rescue ArgumentError, TypeError
      DEFAULT_DAYS
    end

  end
end
