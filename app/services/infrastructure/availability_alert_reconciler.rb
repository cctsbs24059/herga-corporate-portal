# frozen_string_literal: true

module Infrastructure
  class AvailabilityAlertReconciler
    # Reconciles one completed assessment window. Never clears an alert merely
    # because an asset has no data, is absent, or monitoring has stopped.
    def call(period_end:)
      assessments = InfrastructureAvailabilityAssessment
        .where(period_end: period_end)
        .includes(:infrastructure_asset)
        .order(:infrastructure_asset_id, id: :desc)
        .to_a.uniq(&:infrastructure_asset_id)

      counts = { created: 0, updated: 0, cleared: 0, unchanged: 0 }
      assessments.each do |assessment|
        asset = assessment.infrastructure_asset
        next unless asset && asset.status == "Active"

        InfrastructureAvailabilityAlert.transaction do
          # Serialize changes for this asset across concurrent scheduler executions.
          asset.lock!
          alert = InfrastructureAvailabilityAlert.unresolved
            .where(infrastructure_asset_id: asset.id).first

          case assessment.assessment_status
          when "BelowThreshold"
            if alert
              # Do not regress an alert if an older assessment is replayed.
              if assessment.period_end >= alert.assessment_period_end
                alert.update!(
                  last_observed_at: [alert.last_observed_at, assessment.period_end].max,
                  assessment_period_end: assessment.period_end,
                  last_availability_percentage: assessment.availability_percentage,
                  threshold_percentage: assessment.threshold_percentage
                )
                counts[:updated] += 1
              else
                counts[:unchanged] += 1
              end
            else
              # A replay of an old breach must not reopen a cleared alert.
              last_alert = InfrastructureAvailabilityAlert.where(infrastructure_asset_id: asset.id)
                .order(assessment_period_end: :desc, id: :desc).first
              if last_alert && last_alert.assessment_period_end >= assessment.period_end
                counts[:unchanged] += 1
              else
                InfrastructureAvailabilityAlert.create!(
                  infrastructure_asset: asset, status: "Active",
                  first_detected_at: assessment.period_end,
                  last_observed_at: assessment.period_end,
                  assessment_period_end: assessment.period_end,
                  last_availability_percentage: assessment.availability_percentage,
                  threshold_percentage: assessment.threshold_percentage
                )
                counts[:created] += 1
              end
            end
          when "MeetsThreshold"
            if alert && assessment.period_end >= alert.assessment_period_end
              alert.update!(status: "Cleared", cleared_at: assessment.period_end,
                            last_observed_at: [alert.last_observed_at, assessment.period_end].max,
                            assessment_period_end: assessment.period_end,
                            last_availability_percentage: assessment.availability_percentage,
                            threshold_percentage: assessment.threshold_percentage)
              counts[:cleared] += 1
            else
              counts[:unchanged] += 1
            end
          else
            # InsufficientData: preserve current state for administrator review.
            counts[:unchanged] += 1
          end
        end
      end
      counts
    end
  end
end
