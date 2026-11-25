# frozen_string_literal: true

module Infrastructure
  class NotificationRetentionPoliciesController < ApplicationController
    before_action -> { require_portal_permission(:governance_read) },
                  only: %i[index show]

    before_action -> { require_portal_permission(:governance_manage) },
                  except: %i[index show]

    before_action :load_policy, only: %i[show approve suspend]

    def index
      @policies = NotificationRetentionPolicy
                  .order(created_at: :desc, id: :desc)
                  .limit(200)
    end

    def show
      @creator = @policy.events
                        .where(action: "Created")
                        .order(:id)
                        .first&.actor

      @may_approve = portal_can?(:governance_manage) &&
                     @policy.status == "Draft" &&
                     @creator.present? &&
                     actor.present? &&
                     !@creator.to_s.strip.casecmp?(actor.to_s.strip)

      @events = @policy.events.order(created_at: :desc, id: :desc)
    end

    def new
      @policy = NotificationRetentionPolicy.new(retention_days: 365)
    end

    def create
      @policy = NotificationRetentionPolicyManager
                .new(actor: actor)
                .create!(**policy_params.to_h.symbolize_keys)

      redirect_to infrastructure_notification_retention_policy_path(@policy),
                  notice: "Draft policy created."
    rescue ActiveRecord::RecordInvalid,
           ActiveRecord::RecordNotUnique,
           ArgumentError => e

      @policy ||= NotificationRetentionPolicy.new(policy_params)

      flash.now[:alert] = e.message

      render :new, status: :unprocessable_entity
    end

    def approve
      NotificationRetentionPolicyManager
        .new(actor: actor)
        .approve!(
          policy: @policy,
          approval_reference: params.require(:approval_reference)
        )

      redirect_to infrastructure_notification_retention_policy_path(@policy),
                  notice: "Policy approved. No disposal authorised."
    rescue NotificationRetentionPolicyManager::InvalidTransition,
           ArgumentError,
           ActionController::ParameterMissing => e

      redirect_to infrastructure_notification_retention_policy_path(@policy),
                  alert: e.message
    end

    def suspend
      NotificationRetentionPolicyManager
        .new(actor: actor)
        .suspend!(policy: @policy)

      redirect_to infrastructure_notification_retention_policy_path(@policy),
                  notice: "Policy suspended."
    rescue NotificationRetentionPolicyManager::InvalidTransition => e

      redirect_to infrastructure_notification_retention_policy_path(@policy),
                  alert: e.message
    end

    private

    def load_policy
      @policy = NotificationRetentionPolicy.find(params[:id])
    end

    def actor
      current_user.username
    end

    def policy_params
      params.require(:policy).permit(
        :name,
        :reference,
        :retention_days
      )
    end
  end
end