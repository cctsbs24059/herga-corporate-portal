# frozen_string_literal: true

module Infrastructure
  class NotificationLegalHoldsController < ApplicationController
    before_action :require_portal_administrator

    def index
      @holds = NotificationLegalHold.order(placed_at: :desc, id: :desc).limit(200)
    end

    def new
      @hold = NotificationLegalHold.new
    end

    def create
      @hold = NotificationLegalHold.new(hold_params)
      @hold.placed_by = current_user.username
      @hold.placed_at = Time.current
      if @hold.save
        redirect_to infrastructure_notification_legal_holds_path, notice: "Legal hold registered."
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def hold_params
      params.require(:legal_hold).permit(:infrastructure_notification_id, :reference, :reason)
    end
  end
end
