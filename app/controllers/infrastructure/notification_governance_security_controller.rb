# frozen_string_literal: true

module Infrastructure
  class NotificationGovernanceSecurityController < ApplicationController
    before_action -> { require_portal_permission(:governance_read) }

    def index
      @assessment = NotificationGovernanceSecurityAssessment.new.call
    end
  end
end
