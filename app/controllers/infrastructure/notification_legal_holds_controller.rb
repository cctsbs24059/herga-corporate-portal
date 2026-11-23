
# frozen_string_literal: true

module Infrastructure
  class NotificationLegalHoldsController < ApplicationController
    before_action -> { require_portal_permission(:governance_read) },
                  only: :index

    before_action -> { require_portal_permission(:governance_manage) },
                  only: %i[new create release]

    def index
      @holds = NotificationLegalHold
        .order(placed_at: :desc, id: :desc)
        .limit(200)

      @audit_summary = NotificationLegalHoldAuditVerifier.new.call
    end

    def new
      @hold = NotificationLegalHold.new
    end

    def create
      @hold = NotificationLegalHold.new(hold_params)
      @hold.placed_by = current_user.username
      @hold.placed_at = Time.current

      NotificationLegalHold.transaction do
        @hold.save!

        NotificationLegalHoldEvent.create!(
          notification_legal_hold: @hold,
          action: "Placed",
          actor: current_user.username,
          justification: @hold.reason,
          created_at: Time.current
        )
      end

      redirect_to infrastructure_notification_legal_holds_path,
                  notice: "Legal hold registered."
    rescue ActiveRecord::RecordInvalid => e
      @hold.errors.add(:base, e.message) if @hold.errors.empty?
      render :new, status: :unprocessable_entity
    end

    def release
      hold = NotificationLegalHold.find(params[:id])

      NotificationLegalHoldManager.new(
        actor: current_user.username
      ).release!(
        hold: hold,
        justification: params[:justification]
      )

      redirect_to infrastructure_notification_legal_holds_path,
                  notice: "Legal hold released and audited."
    rescue NotificationLegalHoldManager::ReleaseDenied => e
      redirect_to infrastructure_notification_legal_holds_path,
                  alert: e.message
    end

    private

    def hold_params
      params.require(:legal_hold).permit(
        :infrastructure_notification_id,
        :reference,
        :reason
      )
    end
  end
end
