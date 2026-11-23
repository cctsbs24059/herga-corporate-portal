# frozen_string_literal: true

module Infrastructure
  class NotificationRetentionController < ApplicationController
    before_action -> { require_portal_permission(:governance_read) }

    def index
      @assessment = Infrastructure::NotificationRetentionAssessment.new.call
      @governance = Infrastructure::NotificationRetentionGovernance.new.call
    end
  end
end
