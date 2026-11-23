# frozen_string_literal: true

module Infrastructure
  class NotificationGovernanceSecurityController < ApplicationController
    before_action :require_portal_administrator

    def index
      @assessment = NotificationGovernanceSecurityAssessment.new.call
    end
  end
end
