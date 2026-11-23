# frozen_string_literal: true

require "csv"

module Infrastructure
  class OperationalReportsController < ApplicationController
    before_action -> { require_portal_permission(:infrastructure_read) }

    def index
      @report = Infrastructure::OperationalReport.new(params: params).call

      respond_to do |format|
        format.html
        format.csv do
          send_data build_csv,
                    filename: "herga-operational-audit-#{@report.section}-#{Time.current.utc.strftime('%Y%m%d-%H%M%S')}.csv",
                    type: "text/csv; charset=utf-8",
                    disposition: "attachment"
        end
      end
    end

    private

    def build_csv
      CSV.generate(headers: true) do |csv|
        csv << @report.csv_headers
        @report.export_rows.each do |record|
          csv << @report.csv_values(record).map { |value| csv_safe(value) }
        end
      end
    end

    def csv_safe(value)
      return value unless value.is_a?(String)

      value.match?(/\A\s*[=+@-]/) ? "'#{value}" : value
    end
  end
end
