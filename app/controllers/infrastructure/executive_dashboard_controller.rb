# frozen_string_literal: true

module Infrastructure
  class ExecutiveDashboardController < ApplicationController
    before_action -> { require_portal_permission(:infrastructure_read) }

    def index
      @overview = Infrastructure::ExecutiveOverview.new(params: params).call
    end
  end
end
