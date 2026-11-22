# frozen_string_literal: true

module Infrastructure
  class NotificationReportsController < ApplicationController
    before_action :require_portal_administrator

    def index
      @report = Infrastructure::NotificationReportExport.new(
        period: params[:period],
        type: params[:type],
        status: params[:status],
        event_type: params[:event_type]
      )

      respond_to do |format|
        format.html
        format.csv do
          response.headers["Cache-Control"] = "no-store"
          send_data @report.csv,
                    filename: @report.filename,
                    type: "text/csv; charset=utf-8",
                    disposition: "attachment"
        end
      end
    end
  end
end
