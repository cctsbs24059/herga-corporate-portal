# frozen_string_literal: true

module Infrastructure
  class NotificationRetentionController < ApplicationController
    before_action :require_portal_administrator

    def index
      @assessment = Infrastructure::NotificationRetentionAssessment.new.call
    end
  end
end
